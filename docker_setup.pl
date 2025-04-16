#!/usr/bin/env perl

# This script downloads the latest OPL metadata release, and restores the database dump file in that release.

use feature say;
use strict;
use warnings;

use CtrlO::Crypt::XkcdPassword;
use File::Fetch;
use File::Copy;
use File::Path;
use Archive::Tar;
use Mojo::File;
use Mojo::JSON qw(decode_json);

my $ww2 = 'webwork2';
if (-d $ww2)
{
	# webwork2 folder exists, check if it is a git repository
	`git -C $ww2 status  2>/dev/null`;
	die "Directory $ww2 exists, but is not a git repository\n" if ($?);
	say "Found existing webwork2 repository in $ww2";
}
else
{
	say "Getting webwork2 from https://github.com/openwebwork:";
	`git clone https://github.com/openwebwork/webwork2.git $ww2`;
}
print "\n";

my $pg = 'pg';
if (-d $pg)
{
	# pg folder exists, check if it is a git repository
	`git -C $pg status  2>/dev/null`;
	die "Directory $pg exists, but is not a git repository\n" if ($?);
	say "Found existing pg repository in $pg";
}
else
{
	say "Getting pg from https://github.com/openwebwork:";
	`git clone https://github.com/openwebwork/pg.git $pg`;
}
print "\n";

# Check if webwork-open-problem-library is already checked out as webwork-open-problem-library or opl.
# If so, use it.  Otherwise, clone it to opl.
my $OPL = 'webwork-open-problem-library';
if (-d $OPL)
{
	# webwork-open-problem-library exists, check if it is a git repository
	`git -C $OPL status  2>/dev/null`;
	say "Found OPL repository in $OPL";
}
else
{
	$OPL = 'opl';
	if (-d $OPL)
	{
		# opl folder exists, check if it is a git repository
		`git -C $OPL status  2>/dev/null`;
		die "Directory $OPL exists, but is not a git repository\n" if ($?);
		say "Found OPL repository in $OPL";
	}
	else
	{
		say "Cloning webwork-open-problem-library into $OPL";
		`git clone https://github.com/openwebwork/webwork-open-problem-library.git $OPL`;
	}
}
print "\n";

## Download the latest OPL metadata release, and restore the database dump file in that release.
## Based on webwork2/bin/download-OPL-metadata-release.pl

# Store the metadata and table-dump file in a separate folder, OPL_data, outside of the OPL, so that git doesn't
# see it inside the OPL.  Docker will copy from OPL_data to the JSON-SAVED and TABLE-DUMP folders at
# build time, then docker-entrypoint.sh will copy from JSON-SAVED to htdocs/DATA and run restore-OPL-tables.pl.
my $OPL_data = 'OPL_data';
die "Couldn't make $OPL_data\n" unless (-d $OPL_data || mkpath($OPL_data));

say "Downloading latest release OPL metadata and table dump into $OPL_data:\n";
my $releaseDataFF =
	File::Fetch->new(uri => 'https://api.github.com/repos/openwebwork/webwork-open-problem-library/releases/latest');
my $file        = $releaseDataFF->fetch(to => $OPL_data) or die $releaseDataFF->error;
my $path        = Mojo::File->new($file);
my $releaseData = decode_json($path->slurp);
$path->remove;

my $releaseTag = $releaseData->{tag_name};
say "Found OPL METADATA release $releaseTag.";

my $downloadURL = '';
for (@{ $releaseData->{assets} })
{
	$downloadURL = $_->{browser_download_url} if ($_->{name} =~ /tar\.gz$/);
}

die 'Unable to determine download url for OPL metadata release.' if !$downloadURL;

# Download and extract the OPL metadata release.
my $releaseDownloadFF = File::Fetch->new(uri => $downloadURL);
my $releaseFile = $releaseDownloadFF->fetch(to => $OPL_data) or die $releaseDownloadFF->error;
say 'Downloaded release archive, now extracting.';

my $arch = Archive::Tar->new($releaseFile);
die "An error occurred while creating the tar file: $releaseFile" unless $arch;
$arch->setcwd($OPL_data);
$arch->extract;
die "There was an error extracting the metadata release: $arch->error" if $arch->error;

die "The downloaded archive did not contain the expected files."
	unless -e "$OPL_data/webwork-open-problem-library";

# Checkout the release tag in the library clone if it hasn't already been done,
# so it matches the metadata and table-dump
`git -C $OPL fetch --tags origin`;
`git -C $OPL show-ref refs/heads/$releaseTag -q`;
if ($?)
{
	say "Switching OPL clone in $OPL to new branch of release tag $releaseTag.";
	`git -C $OPL checkout -b $releaseTag $releaseTag`;
}

# Remove temporary files.
say "Removing temporary files.";
unlink($releaseFile);
print "\n";

# Docker build will copy this file to $APP_ROOT/libraries/Restore_or_build_OPL_tables so that
# docker-entrypoint.sh will set up the OPL table using the data in $OPL_data
`touch $OPL_data/Restore_or_build_OPL_tables`;

if (-f '.env')
{
	say "Found an existing .env file, so we won't overwrite it.";
	say " If you want a fresh .env, delete the existing one and rerun this script.";
	say " Warning: The webwork db password is set the first time docker runs the";
	say " container.  Changing the password in .env won't change it.  Instead,";
	say " Webwork won't run unless the WEBWORK_DB_PASSWORD in .env matches what was";
	say " set the first time.  You probably don't want a fresh .env unless you have";
	say " deleted the webwork_mysql Docker volume because you are starting over.";
}
else
{
	my $password_generator = CtrlO::Crypt::XkcdPassword->new(wordlist => 'eff_large');
	my $pass = $password_generator->xkcd( words => 3, digits => 3 );

	say "Writing environment file .env for the docker build process, with a randomly";
	say 'generated password for the webwork db.';
	open(ENVFILE, '>.env') || die "Couldn't open file .env, $!";
	print ENVFILE "OPL_PATH=$OPL\n";
	print ENVFILE "WEBWORK2_HTTP_PORT_ON_HOST=8080\n";
	print ENVFILE "WEBWORK_DB_USER=webworkWrite\n";
	print ENVFILE "WEBWORK_DB_PASSWORD='$pass'\n";
	close ENVFILE;
}
print "\n";

say 'Done!  Things to do:';
say '* Run `docker compose build` in this folder to build the WeBWorK image.';
say '  Note that webwork2 and pg are each on their respective main branches.';
say '  You may change either or both branches as needed before invoking docker.';
say '  See';
say '  - https://github.com/openwebwork/webwork2/wiki/First-Time-Setup';
say '  - https://github.com/openwebwork/webwork2/wiki/Coding-and-Workflow';
say '  If you make changes (including changing the branch) to anything in';
say '   webwork2, pg, or the OPL, you need to run `docker compose build` again';
say '   to update the docker image.';
say '* Run `docker compose up -d` in this folder to start the WeBWorK container.';
say '* Run `docker compose down` in this folder to shut down the WeBWorK container.';
1;
