# Build time variables

ARG SRCIMAGE=debian:bookworm-slim


FROM  $SRCIMAGE AS builder

ARG LSMB_VERSION="1.12.10"
ARG LSMB_DL_DIR="Releases"
ARG ARTIFACT_LOCATION="https://download.ledgersmb.org/f/$LSMB_DL_DIR/$LSMB_VERSION/ledgersmb-$LSMB_VERSION.tar.gz"


RUN set -x ; \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y update && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y dist-upgrade && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install dh-make-perl libmodule-cpanfile-perl git wget && \
  apt-file update

RUN set -x ; \
  wget --quiet -O /tmp/ledgersmb-$LSMB_VERSION.tar.gz "$ARTIFACT_LOCATION" && \
  tar -xzf /tmp/ledgersmb-$LSMB_VERSION.tar.gz --directory /srv && \
  rm -f /tmp/ledgersmb-$LSMB_VERSION.tar.gz && \
  cd /srv/ledgersmb && \
  ( ( for lib in $( cpanfile-dump --with-all-features --recommends --no-configure --no-build --no-test ) ; \
    do \
      if dh-make-perl locate "$lib" 2>/dev/null ; \
      then  \
        : \
      else \
        echo no : $lib ; \
      fi ; \
    done ) | grep -v dh-make-perl | grep -v 'not found' | grep -vi 'is in Perl ' | cut -d' ' -f4 | sort | uniq | tee /srv/derived-deps ) && \
  cat /srv/derived-deps


#
#
#  The real image build starts here
#
#


FROM  $SRCIMAGE
LABEL org.opencontainers.image.authors="LedgerSMB project <devel@lists.ledgersmb.org>"
LABEL org.opencontainers.image.title="LedgerSMB double-entry accounting web-application"
LABEL org.opencontainers.image.description="LedgerSMB is a full featured double-entry financial accounting and Enterprise\
 Resource Planning system accessed via a web browser (Perl/JS with a PostgreSQL\
 backend) which offers 'Accounts Receivable', 'Accounts Payable' and 'General\
 Ledger' tracking as well as inventory control and fixed assets handling. The\
 LedgerSMB client can be a web browser or a programmed API call. The goal of\
 the LedgerSMB project is to bring high quality ERP and accounting capabilities\
 to Small and Midsize Businesses."

ARG LSMB_VERSION="1.12.10"
ARG LSMB_DL_DIR="Releases"
ARG ARTIFACT_LOCATION="https://download.ledgersmb.org/f/$LSMB_DL_DIR/$LSMB_VERSION/ledgersmb-$LSMB_VERSION.tar.gz"


### PACKAGE REQUIREMENTS RATIONALE
#
# postgresql-client(from apt.postgresql.org): reduces chances running a newer server than this client
# fonts-liberation: installed for compatibility with templates from 1.8 and earlier

COPY --from=builder /srv/derived-deps /tmp/derived-deps

RUN set -x ; \
  echo -n "APT::Install-Recommends \"0\";\nAPT::Install-Suggests \"0\";\n" >> /etc/apt/apt.conf && \
  mkdir -p /usr/share/man/man1/ && \
  mkdir -p /usr/share/man/man2/ && \
  mkdir -p /usr/share/man/man3/ && \
  mkdir -p /usr/share/man/man4/ && \
  mkdir -p /usr/share/man/man5/ && \
  mkdir -p /usr/share/man/man6/ && \
  mkdir -p /usr/share/man/man7/ && \
  mkdir -p /usr/share/man/man8/ && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y update && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y dist-upgrade && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install \
    wget ca-certificates gnupg iproute2 \
    $( cat /tmp/derived-deps ) \
    texlive-plain-generic texlive-latex-recommended texlive-fonts-recommended \
    texlive-xetex fonts-liberation \
    lsb-release postgresql-common && \
  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y update && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install postgresql-client && \
  DEBIAN_FRONTEND="noninteractive" apt-get -q -y install git cpanminus make gcc libperl-dev && \
  wget --quiet -O /tmp/ledgersmb-$LSMB_VERSION.tar.gz "$ARTIFACT_LOCATION" && \
  tar -xzf /tmp/ledgersmb-$LSMB_VERSION.tar.gz --directory /srv && \
  rm -f /tmp/ledgersmb-$LSMB_VERSION.tar.gz && \
  cpanm --metacpan --notest \
    --with-feature=starman \
    --with-feature=latex-pdf-ps \
    --with-feature=openoffice \
    --installdeps /srv/ledgersmb/ && \
  DEBIAN_FRONTEND="noninteractive" apt-get purge -q -y git cpanminus make gcc libperl-dev && \
  DEBIAN_FRONTEND="noninteractive" apt-get autoremove -q -y && \
  DEBIAN_FRONTEND="noninteractive" apt-get clean -q && \
  rm -rf ~/.cpanm/ /var/lib/apt/lists/* /usr/share/man/*


WORKDIR /srv/ledgersmb

# master requirements

# Configure outgoing mail to use host, other run time variable defaults

## MAIL
# '__CONTAINER_GATEWAY__' is a magic value which will be substituted
# with the actual gateway IP address
ENV LSMB_MAIL_SMTPHOST=__CONTAINER_GATEWAY__
#ENV LSMB_MAIL_SMTPPORT=25
#ENV LSMB_MAIL_SMTPSENDER_HOSTNAME=(container hostname)
#ENV LSMB_MAIL_SMTPTLS=
#ENV LSMB_MAIL_SMTPUSER=
#ENV LSMB_MAIL_SMTPPASS=
#ENV LSMB_MAIL_SMTPAUTHMECH=

## DATABASE
ENV POSTGRES_HOST=postgres
ENV POSTGRES_PORT=5432
ENV DEFAULT_DB=lsmb

COPY start.sh /usr/local/bin/start.sh

RUN chmod +x /usr/local/bin/start.sh && \
  mkdir -p /var/www && \
  mkdir -p /srv/ledgersmb/local/conf && \
  chown -R www-data /srv/ledgersmb/local

# Work around an aufs bug related to directory permissions:
RUN mkdir -p /tmp && chmod 1777 /tmp

# Internal Port Expose
EXPOSE 5762

USER www-data
CMD ["start.sh"]
