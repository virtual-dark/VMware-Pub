
####################################################
# Copyright 2013 VMware, Inc.  All rights reserved.
####################################################
#
# @file SSOConnection.pm
# The file implements SSOConnection perl module.
#
# @copy 2013, VMware Inc.
#

#
# @class SSOConnection
# This class is used for to login with sso server and gets
# the hok or bearer token.
#
package SSOConnection;

#
# Core Perl modules
#
use strict;
use warnings;

#
# @method new
# Constructor
#
# @param cm_url  - CM URL
# @param sso_url  - SSO URL
#
# @return Blessed object
#
sub new {
   my ($class, %args) = @_;
   my $self = {};
   $self->{'cm_url'} = $args{'cm_url'};
   $self->{'sts_url'} = $args{'sso_url'};
   if (!defined($self->{'cm_url'}) && !defined($self->{'sts_url'})) {
      die "The parameter 'cm_url' or 'sso_url' must be set.";
   }
   my $pyexe = __FILE__;
   $pyexe =~ s,SSOConnection.pm$,pyexe/ssoclient,;
   # For windows the ssoclient available on the same dir
   if (!-e $pyexe) {
      $pyexe = __FILE__;
      $pyexe =~ s,SSOConnection.pm$,ssoclient,;
   }
   $self->{Pyexe} = $pyexe;
   return bless( $self, $class );
}

#
#@method login
# Login with username/password and acquire SAML Token. If the public
# and private keys are provided, this method gets the hok token othewise
# gets the bearer token.
#
#@param user_name  - User name
#@param password  - Password
#@param public_key  - Public Key
#@param private_key  - Private Key
#
#@return SAML Token
#
sub login {
   my ($self, %args) = @_;
   my $pyexe = $self->{Pyexe};
   my $username = $args{user_name};
   my $password = $args{password};
   my $public_key = $args{public_key} || undef;
   my $private_key = $args{private_key} || undef;
   my $cm_url = $self->{cm_url};
   my $sts_url = $self->{sts_url};
   my $pyCmd =  "\"$pyexe\"" . " --user=$username --password=$password ";
   if ($sts_url) {
      # Constructing SSO url for IPv6 host
      # e.g. If SSO host provided is in IPv6 format say, https://fe:10:20:30:70e:fe/sts/STSService
      my $sso_host = $sts_url;
      # Triming out, host name/IP from "sso_host" i.e. $2 = "fe:10:20:30:70e:fe"
      if ($sso_host =~ s|http(s?)://(.*)/sts/.*|http$1://$2/sts(.*)|i) {
         $sso_host = $2;
         # Checking if the host specified is in IPv6 format
         if (($sso_host =~ tr/:/:/) > 1){
            if (!($sso_host =~ /]/)){
               # If host is in IPv6 and doesen't have any square bracket then adding it
               $sso_host = "[" . $sso_host . "]";
               # Constructing sso url as "http(s)//[fe:10:20:30:70e:fe]/sts/STSService"
               $sts_url =~ s|http(s?)://(.*)/sts.*|http$1://$sso_host/sts/STSService|i;
            }
         }
      }
      $pyCmd .= " --stsurl=$sts_url";
   } else {
      $pyCmd .= " --cmurl=$cm_url";
   }
   if (defined ($private_key)) {
      $pyCmd .= " --private_key=$private_key --public_key=$public_key";
   }
   $pyCmd .= " |";
   eval {
      open CMD, $pyCmd;
      my $item = undef;
      foreach $item (<CMD>) {
         $self->{SAMLToken} .= $item;
      }
   };
   warn $@ if $@;
   if (!defined $self->{SAMLToken}) {
     die "Couldn't get the SAML token";
   }
   return $self->{SAMLToken};
}

#
#@method get_token
# Returns the SAML Token.
#
#@return SAML Token
#
sub get_token {
   my $self = shift;
   return $self->{SAMLToken};
}

1;
