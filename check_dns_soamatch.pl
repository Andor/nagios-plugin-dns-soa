#!/usr/bin/perl -w

use strict;
use warnings;

use Net::DNS;
use Net::DNS::RR;
use Getopt::Std;
use Data::Dumper;

my %options=();
getopts("da:h:s:n:q:",\%options);
if (!$options{ n} || !$options{ q})
  {
      print "There are no options defined - run this script with :\n"; 
      print "     -d        debug\n";
      print "     -n [name] domain name\n";
      print "     -q [svr]  domain name server to query (master for your domain name)\n";
      print "     -a [api]  stain api server (optional)\n";
      print "     -h [host] stain dns-server hostname (optional)\n";
      print "     -s [srv]  stain service name (optional)\n";
      exit -1;
  }

my $errors  = 0;
my $errortext = ""; 

## Get domain name from user.
my $domain     = $options{ n};
my $objResolve = Net::DNS::Resolver->new;

## If debug requested, turn it on inside Net::DNS
if ($options{ d})
  {
  #  $objResolve->debug(1);
  }

## We need to work out which nameservers are responsible for
#  this domain name.  Put the nameservers in a perl list
#  called @nameservers
my @nameservers;
$objResolve->nameservers("$options{ q}");
my $query = $objResolve->query("$domain", "NS");

if ($query) 
  {
    foreach my $rr (grep { $_->type eq 'NS' } $query->answer) 
      {
        push @nameservers,$rr->nsdname;
	print "Nameserver to query: " . $rr->nsdname, "\n" if $options{ d};
      }
  } else {
    warn "query failed: ", $objResolve->errorstring, "\n";
    exit -1;
  }

## Also find the SOA serial number to use as the master serial.
my $master;
$query  = $objResolve->query("$domain", "SOA");
foreach my $rr (grep { $_->type eq 'SOA' } $query->answer)
  {
    $master = $rr->serial;
    print "Master serial number from $options{ q} is $master\n" if $options{ d};
  }

foreach my $server (@nameservers)
  {
    next if ($server eq $options { q});
    print "Checking server ... $server\n" if $options{ d};
    my $objChildResolve = Net::DNS::Resolver->new;
  #  $objChildResolve->debug(1) if $options{ d};
    $objChildResolve->nameservers("$server");
    my $query        = $objChildResolve->query("$domain", "SOA");
    foreach my $rr (grep { $_->type eq 'SOA' } $query->answer)
      {
        my $childserial = $rr->serial;
        print "Serial number from $server is $childserial\n" if $options{ d};
        if ($childserial != $master)
          {
            $errors++;
            $errortext .= "$server serves Serial $childserial not $master  ";
          }
      }
  }

# We have counted the number of errors - if there have been any errors at
# all, just record the number and set $errors to the eventual return code
# of 2.

if ($errors gt 0)
  {
    $errortext .= " ($errors errors).\n";
    $errors     = 2;
  } else {
    $errortext  = "Everything OK testing domain $options{ n}.\n";
  }

if ($options{ a})
  {
    if (!$options{ h} || !$options{ s})
      {
        die "No hostname or service name defined, yet Stain requested.";
      }
    # Pass result into stain and dispatch.
    require SubmitCheckResults;
    my %tosend = (
               hostname => $options{ h},
               service  => $options{ s},
               apihost  => $options{ a},
               statustext => $errortext,
               status     => $errors
             );

    SubmitCheckResults::send(%tosend); 
  }

print $errortext;
exit $errors;
