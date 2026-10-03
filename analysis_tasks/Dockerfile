FROM r-base:3.5.0

# Local install patch: current CRAN packages require R >= 4, so install the
# versions that were current in late 2019 from a dated CRAN snapshot, and fail
# the build if any package did not install.
RUN R --slave --silent --vanilla \
    -e 'options(Ncpus = parallel::detectCores())' \
    -e 'install.packages(c("optparse", "caret", "plyr", "gbm", "doParallel"), repos="https://packagemanager.posit.co/cran/2019-10-01")' \
    -e 'for (p in c("optparse", "caret", "plyr", "gbm", "doParallel")) library(p, character.only = TRUE)'

RUN mkdir -p /opt/analysis_tasks
WORKDIR /opt/analysis_tasks

COPY . /opt/analysis_tasks

# Provide access to the R environment by default if run without parameters
CMD ["R", "--vanilla"]
