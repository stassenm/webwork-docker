FROM ubuntu:24.04 AS webwork2

ENV WEBWORK_URL=/webwork2
ENV WEBWORK_ROOT_URL=http://localhost:8080
ENV WEBWORK_SMTP_SERVER=localhost
ENV WEBWORK_TIMEZONE=America/New_York
ENV APP_ROOT=/opt/webwork
ENV WEBWORK_ROOT=$APP_ROOT/webwork2
ENV PG_ROOT=$APP_ROOT/pg

ENV SSL=0
ENV PAPERSIZE=letter
ENV SYSTEM_TIMEZONE=UTC
ENV ADD_LOCALES=0
ENV ADD_APT_PACKAGES=0

ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NONINTERACTIVE_SEEN=true
ARG ADDITIONAL_BASE_IMAGE_PACKAGES
RUN apt-get update && apt-get install -y --no-install-recommends \
	apt-utils \
	ca-certificates \
	cpanminus \
	culmus \
	curl \
	debconf-utils \
	dvipng \
	dvisvgm \
	fonts-linuxlibertine \
	gcc \
	git \
	imagemagick \
	iputils-ping \
	jq \
	libarchive-extract-perl \
	libarchive-zip-perl \
	libarray-utils-perl \
	libc6-dev \
	libcapture-tiny-perl \
	libclass-tiny-antlers-perl \
	libclass-tiny-perl \
	libcpanel-json-xs-perl \
	libcrypt-jwt-perl \
	libcryptx-perl \
	libdata-dump-perl \
	libdata-structure-util-perl \
	libdatetime-perl \
	libdbd-mysql-perl \
	libdevel-checklib-perl \
	libemail-address-xs-perl \
	libemail-date-format-perl \
	libemail-sender-perl \
	libemail-stuffer-perl \
	libexception-class-perl \
	libextutils-config-perl \
	libextutils-helpers-perl \
	libextutils-installpaths-perl \
	libextutils-xsbuilder-perl \
	libfile-copy-recursive-perl \
	libfile-find-rule-perl-perl \
	libfile-sharedir-install-perl \
	libfuture-asyncawait-perl \
	libgd-barcode-perl \
	libgd-perl \
	libhtml-scrubber-perl \
	libhtml-template-perl \
	libhttp-async-perl \
	libiterator-perl \
	libiterator-util-perl \
	libjson-maybexs-perl \
	libjson-perl \
	libjson-xs-perl \
	liblocale-maketext-lexicon-perl \
	libmariadb-dev \
	libmath-random-secure-perl \
	libmime-base32-perl \
	libmime-tools-perl \
	libminion-backend-sqlite-perl \
	libminion-perl \
	libmodule-build-perl \
	libmodule-pluggable-perl \
	libmojolicious-perl \
	libmojolicious-plugin-renderfile-perl \
	libnet-https-nb-perl \
	libnet-ip-perl \
	libnet-ldap-perl \
	libnet-oauth-perl \
	libossp-uuid-perl \
	libpadwalker-perl \
	libpandoc-wrapper-perl \
	libpath-class-perl \
	libpath-tiny-perl \
	libphp-serialization-perl \
	libpod-wsdl-perl \
	libsoap-lite-perl \
	libsql-abstract-perl \
	libstring-shellquote-perl \
	libsub-uplevel-perl \
	libsvg-perl \
	libtemplate-perl \
	libtest-deep-perl \
	libtest-exception-perl \
	libtest-fatal-perl \
	libtest-mockobject-perl \
	libtest-pod-perl \
	libtest-requires-perl \
	libtest-warn-perl \
	libtest-xml-perl \
	libtext-csv-perl \
	libthrowable-perl \
	libtimedate-perl \
	libuniversal-can-perl \
	libuniversal-isa-perl \
	libuuid-tiny-perl \
	libxml-parser-easytree-perl \
	libxml-parser-perl \
	libxml-semanticdiff-perl \
	libxml-simple-perl \
	libxml-writer-perl \
	libxml-xpath-perl \
	libyaml-libyaml-perl \
	lmodern \
	locales \
	make \
	mariadb-client \
	netpbm \
	patch \
	pdf2svg \
	preview-latex-style \
	ssl-cert \
	sudo \
	texlive \
	texlive-lang-arabic \
	texlive-lang-other \
	texlive-latex-extra \
	texlive-plain-generic \
	texlive-science \
	texlive-xetex \
	tzdata \
	zip $ADDITIONAL_BASE_IMAGE_PACKAGES \
	&& curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
	&& apt-get install -y --no-install-recommends nodejs \
	&& apt-get clean \
	&& rm -fr /var/lib/apt/lists/* /tmp/*

# Install additional Perl modules from CPAN that are not packaged for Ubuntu or are outdated in Ubuntu.
RUN cpanm install -n \
	Statistics::R::IO \
	DBD::MariaDB \
	Perl::Tidy@20240903 \
	Archive::Zip::SimpleZip \
	&& rm -fr ./cpanm /root/.cpanm /tmp/*

RUN mkdir -p /www/www/html

# Create the /etc/ssl/local directory in case it is needed.
RUN mkdir /etc/ssl/local
RUN chown www-data /etc/ssl/local
RUN chmod -R u+w /etc/ssl/local
RUN echo "en_US ISO-8859-1\nen_US.UTF-8 UTF-8" > /etc/locale.gen \
	&& /usr/sbin/locale-gen \
	&& echo "locales locales/default_environment_locale select en_US.UTF-8\ndebconf debconf/frontend select Noninteractive" > /tmp/preseed.txt \
	&& debconf-set-selections /tmp/preseed.txt \
	&& rm /etc/localtime /etc/timezone && echo "Etc/UTC" > /etc/timezone \
	&& dpkg-reconfigure -f noninteractive tzdata

RUN mkdir -p $APP_ROOT/courses
RUN chown www-data $APP_ROOT/courses
RUN chmod -R u+w $APP_ROOT/courses
VOLUME $APP_ROOT/courses

RUN mkdir -p /run/webwork2
RUN chown www-data /run/webwork2
RUN chmod -R u+w /run/webwork2

# Set up the OPL
ARG OPL=opl
COPY --link $OPL $APP_ROOT/libraries/webwork-open-problem-library
COPY OPL_data/webwork-open-problem-library/JSON-SAVED $WEBWORK_ROOT/htdocs/DATA
COPY OPL_data/webwork-open-problem-library/TABLE-DUMP $APP_ROOT/libraries/webwork-open-problem-library/TABLE-DUMP
COPY OPL_data/Restore_or_build_OPL_tables $APP_ROOT/libraries/Restore_or_build_OPL_tables

# Set up webwork2
COPY --link webwork2 $APP_ROOT/webwork2
RUN cd $APP_ROOT/webwork2/ \
		&& chown www-data DATA logs tmp \
		&& chmod -R u+w DATA logs tmp
RUN cd $WEBWORK_ROOT/htdocs \
		&& npm install

# Set up pg
COPY --link pg $APP_ROOT/pg
COPY patches/pgfsys-dvisvmg-bbox-fix.patch /tmp
RUN cd $PG_ROOT/htdocs \
		&& npm install \
		&& patch -p1 -d / < /tmp/pgfsys-dvisvmg-bbox-fix.patch \
		&& rm /tmp/pgfsys-dvisvmg-bbox-fix.patch

EXPOSE 8080
WORKDIR $WEBWORK_ROOT
RUN echo "PATH=$PATH:$APP_ROOT/webwork2/bin" >> /root/.bashrc
COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["sudo", "-E", "-u", "www-data", "hypnotoad", "-f", "bin/webwork2"]
