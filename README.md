# vimexx-dns

Use the API to manipulate DNS records for domains hosted on Vimexx.eu.

# Description

This script uses the Vimexx API to add or delete DNS records for a domain
hosted by the Vimexx nameservers.

The main purpose of this script is to automate the creation and renewal of
[Let's Encrypt](https://letsencrypt.org/) SSL certificates, using [Certbot](https://certbot.eff.org/) to validate domain
ownership using a [DNS-01 challenge](https://letsencrypt.org/docs/challenge-types/), and to automate this procedure.

It is also possible to update an A record in a domain with the current
dynamic IP address of your internet connection, thus avoiding the use of
a dynamic DNS service, and instead, use your own domain to keep track of
any dynamic IP addresses you have.

# Installation

## Using apt on Debian

Add the [vimexx-dns repository](https://repo.qb21.nl) to your system, then download the most recent version.

```
sudo apt install vimexx-dns
```
As a bonus, it's easy to remain up-to-date!

## Manually

Simply copy the script vimexx-dns to any location, then install the necessary dependencies.

### Dependencies

```
sudo apt install libappconfig-std-perl libjson-perl libnet-dns-perl
```

# Setup

## Vimexx API credentials

This script will require access to the API provided by Vimexx.

- Login to your accout at [Vimexx](https://my.vimexx.eu/)
- Create a [WHMCS API secret](https://my.vimexx.eu/api)
- Take note of the Client ID and the Client Secret

## Create a configuration file

The script will search for a configuration file in the following locations:

- /etc/vimexx-dns.conf
- $HOME/.vimexx-dns
- .vimexx-dns in the working directory

The configuration should contain this:

```
[login]
id = <Client ID>
secret = <Client Secret>
username = <Your Vimexx username>
password = <Your Vimexx password>
```

(!) Be carefull where and how you keep this file, as it will allow full access to your DNS records.

# Usage

```
Usage:
    vimexx-dns [OPTION]... DOMAIN [CONTENT]

Options and Arguments:
      -t,-record_ttl     Specify DNS TTL. Valid values are 24h (the default),
                         8h, 4h, 2h, 1h, 10m and 5m.
      -n,-nons           Do NOT use an authorative nameserver to find the actual TTL
                         of a DNS record. When this is set, all records will be set to
                         the TTL specified with -t.

      -d,-delete         Deletes the most recently added record, but only if
                         it was added in the last 600 seconds.
      -c,-clear          Clears the cache with the authentication token and
                         the DNS records, forcing renewal.

         -ddns           Run in dynamic DNS mode, obtaining the current IPv4
                         address and updating an A record.

         -help           Print this info
         -verbose        Verbose output
         -debug          Debug output
      -q,-quiet          Surpress all output

         -login_id       Vimexx API id
         -login_secret   Vimexx API secret
         -login_username Vimexx login
         -login_password Vimexx password

         -cache          Set location of cache - defaults to '/dev/shm/vimexx.cache'

         -getip          Set URL which returns public IPv4 - defaults to 'http://icanhazip.com'
```

Please note that due to a limitation in the Vimexx API, the DNS records returned by an API call do not include TTL (Time To Live) information. Additionally, it is not possible to update individual DNS records — any update requires rewriting all records.

To avoid resetting the TTL of all DNS records to the default value each time a change is made, this script, by default, queries an authoritative nameserver for each DNS record returned by the Vimexx API to retrieve the current TTL.

This behavior can be disabled using the `-nons` option. However, if this option is used and the DNS records need
an update, then the TTL for *all* DNS records will be set to `'24h'` (or to the value specified in the configuration file or as a command-line argument).

# Integration with Certbot

## Install Certbot

The first step is installing Certbot on a secure host, preferably not a public-facing (web) server.
Follow the instructions provided [here](https://certbot.eff.org/instructions).

## Requesting a new certificate

Run the following command to request a new certificate for a domain `your.domain.com`

```
certbot certonly --manual --manual-auth-hook authenticator.sh --manual-cleanup-hook cleanup.sh --preferred-challenges dns -d your.domain.com
```

This does the following:

- A DNS-01 challenge is generated
- certbot executes the script 'authenticator.sh' which must create the requested DNS record for your domain
- The DNS record that was created will be checked, and if succesfull, a new Let's Encrypt certificate will be made available
- Certbot will then execute the script `cleanup.sh', which should remove the DNS record that was previously created

### authenticator.sh

```
# cat authenticator.sh
#!/bin/sh
/path/to/vimexx-dns $CERTBOT_DOMAIN $CERTBOT_VALIDATION
# Give DNS some time to properly propagate
sleep 15
```

### cleanup.sh

```
# cat cleanup.sh
#!/bin/sh
/path/to/vimexx-dns -d $CERTBOT_DOMAIN
```

This script is also the ideal place to copy the freshly generated certificates to the actual (web) server that requires the certificates.
This can be easily automated with a combination of SSH and public/private key authentication.

## Renewing a certificate

Let's Encrypt certificates are valid for 3 months. It will only be possible to renew a certificate when the expiration date is less that a month or so. It is recommended to try and renew all your certificates every day. Any certificates that are not yet up for renewal will simply be skipped.

```
# Renew a single certificate
certbot --cert-name your.domain.com --preferred-challenges dns renew
```

```
# Renew all certificates
certbot --preferred-challenges dns renew
```

# Running as a dynamic DNS client

```
vimexx-dns -ddns myhomeserver.example.com
```
This will create or update the DNS A record for 'myhomeserver.example.com' with your current public IPv4 address.

## Using the docker image

A [docker image](https://hub.docker.com/repository/docker/2kman/vimexx-ddns-client/general) to keep your A record in sync with your current public IPv4 address is also available.

The docker container needs access to your secrets. Create a configuration file as shown above, and write it somewhere secure where docker has access to it, then add it to your docker container as shown below in the Docker Compose configuration file.

This is an example Docker Compose configuration file:

- Set the domain with VIMEXX_DNS_DOMAIN, in this example, 'your.domain.com'
- Set how often the container should check for a modified local IP address, by default 30 seconds

```
services:
  vimexx-ddns-client:
    tty: true
    container_name: vimexx-ddns-client
    image: 2kman/vimexx-ddns-client:alpine
    restart: unless-stopped
    volumes:
      - /path/to/secure/config/file:/etc/vimexx-dns.conf:ro
    environment:
      - VIMEXX_DNS_DOMAIN=your.domain.com
      - VIMEXX_SLEEP=30
```

This can also be used directly to create a [Portainer stack](https://docs.portainer.io/user/docker/stacks/add).
