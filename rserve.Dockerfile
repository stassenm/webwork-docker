FROM r-base AS rserve

# Get the latest Rserve from Rforge
RUN install2.r --error -r "http://rforge.net" Rserve

# Install additional packages from CRAN
ARG ADDITIONAL_R_PACKAGES
RUN install2.r dplyr lpSolve tseries zoo ${ADDITIONAL_R_PACKAGES}\
    && rm -rf /tmp/downloaded_packages

VOLUME /localdata
EXPOSE 6311
ENTRYPOINT ["R", "-e", "Rserve::run.Rserve(remote=TRUE, auth=FALSE, daemon=FALSE)"]
