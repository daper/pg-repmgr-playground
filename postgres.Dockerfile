FROM postgres:10

RUN apt-get update -y \
    && apt-get install -y \
      openssh-server \
      openssh-client \
      vim \
      apt-transport-https \
      wget \
      sudo \
      net-tools \
      iputils-ping \
      rsync \
    && sed -Ei 's/^postgres:!:(.*)$/postgres:*:\1/' /etc/shadow \
    && echo "postgres ALL = NOPASSWD: /etc/init.d/repmgrd" \
      >> /etc/sudoers.d/postgres \
    && echo "postgres ALL = NOPASSWD: /usr/bin/pg_ctlcluster" \
      >> /etc/sudoers.d/postgres

RUN echo "deb https://dl.2ndquadrant.com/default/release/apt stretch-2ndquadrant main" \
      > /etc/apt/sources.list.d/2ndquadrant.list \
    && wget --quiet -O - https://dl.2ndquadrant.com/gpg-key.asc \
      | apt-key add - \
    && apt-get update -y \
    && apt-get install -y postgresql-10-repmgr

COPY entrypoint.sh /entrypoint.sh

VOLUME "/etc/postgresql"
ENTRYPOINT ["/entrypoint.sh"]