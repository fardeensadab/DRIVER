FROM node:8-slim

# Local install patch: Debian 9 (stretch) moved to archive.debian.org, and
# GitHub no longer serves the unauthenticated git:// protocol used by bower.
RUN echo "deb http://archive.debian.org/debian stretch main" > /etc/apt/sources.list && \
  echo "deb http://archive.debian.org/debian-security stretch/updates main" >> /etc/apt/sources.list && \
  echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  git \
  libfontconfig \
  ruby \
  ruby-dev \
  python \
  python-dev \
  && rm -rf /var/lib/apt/lists/* && \
  npm install -g --save grunt-cli@1.2.0 bower@1.8.14  # local install patch: newer grunt-cli needs Node >= 10

RUN git config --global url."https://github.com/".insteadOf git://github.com/

RUN gem install ffi -v 1.9.18
RUN gem install sass -v 3.4.22
RUN gem install rb-inotify -v 0.9.10
# Local install patch: pin compass and its deps (latest multi_json needs Ruby >= 3.2)
RUN gem install multi_json -v 1.15.0
RUN gem install chunky_png -v 1.3.15
RUN gem install compass -v 1.0.3

RUN mkdir -p /opt/schema_editor /npm /bower

WORKDIR /npm
COPY package.json /npm/
# Local install patch: without a lockfile npm hoists the newest tough-cookie,
# which uses syntax Node 8 cannot parse (breaks bower/cdnify); pin it.
RUN npm install && npm install --no-save tough-cookie@2.5.0

WORKDIR /bower
COPY bower.json /bower/
RUN bower install --allow-root --config.interactive=false --force

WORKDIR /opt/schema_editor
COPY . /opt/schema_editor

ENTRYPOINT ["grunt"]
