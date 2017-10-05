#!/usr/bin/perl -w
###############################################################
##  Script     : globalPermissions
##  Author     : Kevin Guimbeau 
##  Date       : 05/10/2017
##  Last Edited: 05/10/2017, Kevin Guimbeau
##  Description: Configuration Global Permission vSphere 6.X
###############################################################
use strict;
use warnings;
use HTTP::Cookies;
use LWP::UserAgent;
use Net::SSL;
use URI::Escape;

use Data::Dumper;
use Getopt::Long qw(:config no_auto_abbrev);

my ($vc_server, $vc_username, $vc_password, $vc_user, $global_action, $vc_role_id, $propagate, $debug, $timeout);
my $result_opts = GetOptions(
    'help|h'                    => sub { printHelpAndExit(); },
    'vc_server=s'               => \$vc_server,
    'vc_username=s'             => \$vc_username,
    'vc_password=s'             => \$vc_password,
    'vc_user=s'                 => \$vc_user,
    'global_action=s'           => \$global_action,
    'vc_role_id=s'              => \$vc_role_id,
    'propagate=s'               => \$propagate,
    'debug=s'                   => \$debug,
    'timeout=s'                 => \$timeout,
);

# No ARGV should be leaved there
if(scalar(@ARGV))
{
    warn("Options not recognised : ".join(" ", @ARGV) . "\n");
    printHelpAndExit();
}
if (not $vc_server)
{
    warn("at least one param (vc_server) must be given !\n");
    printHelpAndExit();
}
if (not $vc_username)
{
    warn("at least one param (vc_username) must be given !\n");
    printHelpAndExit();
}
if (not $vc_password)
{
    warn("at least one param (vc_password) must be given !\n");
    printHelpAndExit();
}
if (not $vc_user)
{
    warn("at least one param (vc_user) must be given !\n");
    printHelpAndExit();
}

if(not $global_action or $global_action !~ /^(add|remove)$/)
{
    warn("at least one param (global_action) must be given (add|remove)!\n");
    printHelpAndExit();
}

if($global_action eq 'add')
{
    if (not $vc_role_id)
    {
        warn("at least one param (vc_role_id) must be given !\n");
        printHelpAndExit();
    }

    if(not $propagate)
    {
        print "'propagate' not defined, default value = 'false'\n";
        $propagate = 'false';
    }
}

if(not $timeout)
{
    print "'timeout' not defined, default value = '90'\n";
    $timeout = 90;
}

my $mob_host    = 'https://'.$vc_server;
my $mob_url     = '';
if($global_action eq 'add')
{
    $mob_url     = '/invsvc/mob3/?moid=authorizationService&method=AuthorizationService.AddGlobalAccessControlList';
}
else
{
    $mob_url     = '/invsvc/mob3/?moid=authorizationService&method=AuthorizationService.RemoveGlobalAccess';
}
my $fullUrl = $mob_host.$mob_url;

if($debug)
{
    print 'FULL URL -> '.$fullUrl."\n";
}

###           ###
#### Cookies ####
###           ###

print "Create cookies config\n";
my $cookie_jar = HTTP::Cookies->new(
    autosave       => 1,
    ignore_discard => 1,
);


###           ###
#### Browser ####
###           ###

print "Create Request config\n";
my $AuthRequest = HTTP::Request->new('GET' => $fullUrl);
$AuthRequest->authorization_basic($vc_username, $vc_password);

print "Create UserAgent config\n";
my $Browser = LWP::UserAgent->new(
    ssl_opts    => { verify_hostname => 0 },
    keep_alive  => 1,
);
$Browser->timeout($timeout);
$Browser->cookie_jar($cookie_jar);

my $response = $Browser->request($AuthRequest);
if($response->is_success)
{
    print "Success to login to vSphere MOB\n";
}
else
{
    print "Failed to login to vSphere MOB\n";
    warn($response);
    die $response->status_line;
}
my $html = $response->content;

if($debug)
{
    # Print Dumper $html;
    print "RESPONSE +++++ RESPONSE\n";
    print Dumper $response;
}

my $info = parseInformation(
    vc_user         => $vc_user,
    html            => $html,
    global_action   => $global_action,
);
my $sessionnonce    = $info->{sessionnonce};
my $body            = $info->{body};

my $RequestGlobalPermissions = HTTP::Request->new(
    'POST' => $fullUrl,
);
$RequestGlobalPermissions->content($body);

$RequestGlobalPermissions->header( 'Host'                       => $vc_server);
$RequestGlobalPermissions->header( 'Accept'                     => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
$RequestGlobalPermissions->header( 'Accept-LangBrowserge'       => 'en-US,en;q=0.5');
$RequestGlobalPermissions->header( 'Accept-Encoding'            => 'gzip, deflate, br');
$RequestGlobalPermissions->header( 'Content-Type'               => 'application/x-www-form-urlencoded');
$RequestGlobalPermissions->header( 'Referer'                    => $fullUrl);
$RequestGlobalPermissions->header( 'Connection'                 => 'keep-alive');
$RequestGlobalPermissions->header( 'Upgrade-Insecure-Requests'  => '1');

my $response2 = $Browser->request($RequestGlobalPermissions);
if($response2->is_success)
{
    print "Success to $global_action global permissions for user : $vc_user\n";
}
else
{
    print "Failed to $global_action global permissions for user : $vc_user\n";
    warn($response2);
    die $response2->status_line;
}

if($debug)
{
    # Print Dumper $html;
    print Dumper $response2;
}

my $Logout = HTTP::Request->new('GET' => "https://$vc_server/invsvc/mob3/logout");
my $response3 = $Browser->request($Logout);
if($response3->is_success)
{
    print "Success to logout out of vSphere MOB\n";
}
else
{
    print "Failed to logout out of vSphere MOB\n";
    warn($response3);
    die $response3->status_line;
}
if($debug)
{
    # Print Dumper $html;
    print Dumper $response3;
}

exit;

sub internalError
{
    print "INTERNAL_ERROR\n";
    exit 0;
}

sub parseInformation
{
    my %params = @_;
    my $username    = $params{vc_user}  || die 'MISSING vc_user';
    my $html_content= $params{html}     || die 'MISSING html';

    my $vc_user_escaped = uri_escape_utf8( $vc_user );
    my @lines = split(/\n/, $html_content);
    my $sessionnonce = undef;
    foreach my $line ( @lines )
    {
        chomp ($line);
        if($line =~ /<input name="vmware-session-nonce" type="hidden" value="([0-9a-z-]+)">/)
        {
            $sessionnonce = $1;
        }
        else
        {
            #print "Line not match\n";
        }
    }

    if(not $sessionnonce)
    {
        warn('Not found vmware-session-nonce');
        die;
    }

    print "VMware session nonce : $sessionnonce\n";

    my $body = '';
    if($global_action eq 'add')
    {
        $body = "vmware-session-nonce=$sessionnonce&permissions=%3Cpermissions%3E%0D%0A+++%3Cprincipal%3E%0D%0A++++++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A++++++%3Cgroup%3Efalse%3C%2Fgroup%3E%0D%0A+++%3C%2Fprincipal%3E%0D%0A+++%3Croles%3E$vc_role_id%3C%2Froles%3E%0D%0A+++%3Cpropagate%3E$propagate%3C%2Fpropagate%3E%0D%0A%3C%2Fpermissions%3E";
    }
    else
    {
        $body = "vmware-session-nonce=$sessionnonce&principals=%3Cprincipals%3E%0D%0A+++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A+++%3Cgroup%3Efalse%3C%2Fgroup%3E%0D%0A%3C%2Fprincipals%3E";
    }
    return {
        sessionnonce    => $sessionnonce,
        body            => $body,
    };
}


sub printHelpAndExit
{
    print "== Help ==
Usage : $0
  --help                                    : display this helps and exits
  --vc_server=<172.XXX.YYY.ZZZ>             : Address Ip for vCenter IP ( vlan 1000 ) - vCenter Server Hostname or IP Address
  --vc_username=<xxxx>                      : username for connection on vCenter
  --vc_password=<xyxyxyxyxy>                : clear password for connection on vCenter
  --vc_user=<iiiii>                         : Name of the user to remove global permission on
  --global_action=<add|remove>              : Add or Remove global permission on
  --vc_role_id=<-1>                         : The ID of the vSphere Role
  --propagate=<false|true>                  : re assign user role
  --debug=<0|1>                             : enable debug mode
  --timeout=<mm>                            : change timeout PUT ( default : 90 )
";

    exit 0;
}


