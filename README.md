# webwork-docker

**Note:** This is not an official [openwebwork](https://github.com/openwebwork) project.  Rather, it is a personal attempt to update, improve, and document the Docker setup for WeBWorK.  See [RATIONALE](https://github.com/stassenm/webwork-docker/blob/main/RATIONALE) for details.

webwork-docker consists of a Perl script plus files needed to set up [WeBWorK](https://github.com/openwebwork) in a Docker container, derived from components of [openwebwork/webwork2](https://github.com/openwebwork/webwork2).  This is meant to replace the Docker setup currently included in [webwork2](https://github.com/openwebwork/webwork2).

## Prerequisites

You will need git, perl, and [Docker Desktop](https://docs.docker.com/get-started/get-docker/).

* [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) runs on the current and two previous major macOS releases.
* [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) runs on [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/en-us/windows/wsl/) in Windows 10 and 11.
* [Docker Desktop for Linux](https://docs.docker.com/desktop/setup/install/linux/) supports Ubuntu, Debian, Red Hat, and Fedora.

The docker_setup.pl script uses the Mojo and CtrlO::Crypt::XkcdPassword packages, so you will need those, too.  Assuming you use `cpanm`:

```shell
cpanm Mojo CtrlO::Crypt::XkcdPassword
```

## Get the webwork-docker files

If you haven't already done so, `cd` into the folder where you want `webwork-docker` to live, and then:

```shell
git clone https://github.com/stassenm/webwork-docker.git
```

## Set up for Docker

Run the docker_setup.pl perl script:

```shell
cd webwork-docker
./docker_setup.pl
```

The script does the following:

1. Clones [webwork2](https://github.com/openwebwork/webwork2), unless webwork-docker/webwork2 is already present.
2. Clones [pg](https://github.com/openwebwork/pg), unless webwork-docker/pg is already present.
3. Clones the [webwork-open-problem-library](https://github.com/openwebwork/webwork-open-problem-library) into webwork-docker/opl, unless it is already checked out in webwork-docker/opl or webwork-docker/webwork-open-problem-library.
4. Downloads the latest release of the OPL metadata and database dump file into `webwork-docker/OPL_data/`, and switches the cloned OPL branch to match. (This step is based on [webwork2/bin/download-OPL-metadata-release.pl](https://github.com/openwebwork/webwork2/blob/main/bin/download-OPL-metadata-release.pl))
5. Writes a `.env` file  with environment variables needed in the docker build process, unless one is already present. In particular, the .env file tells docker whether the OPL is in webwork-docker/opl or webwork-docker/webwork-open-problem-library (depending on step 3) and sets a random password for the webwork db user.

## Build the Docker image

```shell
docker compose build
```

Docker compose reads the .env, compose.yaml, and Dockerfile files for directions to build the image from the contents of the webwork2, pg, opl, and OPL_data directories.  This will take a few minutes.

## Start the webwork container

You can start the container in the foreground:

```shell
docker compose up
```

You will see all the Docker output as the container is brought up, along with any messages webwork throws as it runs. You will need a second terminal (or the Docker Desktop app) to tell the container to stop.

Alternatively, you can start the container in the background (`detached`):

```shell
docker compose up -d
```

You will see minimal output from Docker and get a terminal prompt as soon as the container is running.

Once the container is running, you can access it at `http://localhost:8080/webwork2/`.

## Stop the webwork container

```shell
docker compose down
```

## Making changes

Docker containers start up from the built image.  In general, changes made in a running container last until the container is brought down.  They don't change the image, so they won't be there the next time the container is brought up. Specific directories may be mounted for persistent storage, however, which separates them from the image. The `compose.yaml` file in webwork-docker specifies persistent volumes for the webwork database, configuration files, and courses, so they should persist from one run of the container to the next.  Everything else reverts to the image on new runs.

To test changes to anything in webwork2, pg, or the OPL, you should make those changes in their respective directories in the webwork-docker folder, then run `docker compose build` again to update the docker image, then `docker compose up` to run the updated container with your changes.

The `docker_setup.pl` script checked out webwork2 and pg on their respective main branches. Development work should usually be done on a branch of your personal fork of the `develop` branch of webwork2 or pg.  See:

* [First Time Setup](https://github.com/openwebwork/webwork2/wiki/First-Time-Setup)
* [Coding and Workflow](https://github.com/openwebwork/webwork2/wiki/Coding-and-Workflow)
