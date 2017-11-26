#!/usr/bin/perl
use strict;
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
use Data::Dumper;
require JSON;
binmode STDOUT, ':utf8';
require utf8;

use Encode;
use lib '/root/software/OvhApi-perl-1.1';
use OvhApi;

# LIB SDK VMWARE
# Connect on www.vmware.com
# SDK LIB -> https://my.vmware.com/web/vmware/details?downloadGroup=SDKPERL600&productId=491
# Download product for your environnement 
# After download and untar file - example Linux 64 : 
#
# [DEMO] - root :~/software # cd vmware-vsphere-cli-distrib/
# [DEMO] - root :~/software/vmware-vsphere-cli-distrib # 
# [DEMO] - root :~/software/vmware-vsphere-cli-distrib # perl Makefile.PL
# [DEMO] - root :~/software/vmware-vsphere-cli-distrib # make
# [DEMO] - root :~/software/vmware-vsphere-cli-distrib # make install
# [DEMO] - root :~/software/vmware-vsphere-cli-distrib # apt-get install liburi-perl libxml-libxml-simple-perl libcrypt-ssleay-perl 
#
#
# Doc http://pubs.vmware.com/vsphere-60/index.jsp#com.vmware.wssdk.apiref.doc/right-pane.html
use VMware::VIRuntime;

my $context = getContext();

my $vmName = $ARGV[0];
if(not $vmName)
{
    die('Missing vm name !');
}

##
### 1er Partie connexion 
##

# On set les options d'authentification :
Opts::set_option('server', $context->{'server'});
Opts::set_option('username', $context->{'username'});
Opts::set_option('password', $context->{'password'});

# On se connecte
print "Connecting ...\n";
Util::connect();
<STDIN>;
print "Connected \n";

my $threshold = 20;
#
# [ Action!!!  ]
#

my $DatacenterView = '';

# Chargement de la vue du datacentre

print "Find datacenter view.\n";
<STDIN>;
eval{
    $DatacenterView  = Vim::find_entity_view(
        'view_type'     => 'Datacenter', 
        'filter'        => {'name'=> $context->{'datacenterName_Labs'}},
        'properties'    => ['name'], 
    );
};
if($@)
{
    print "Failed to get DatacenterView\n";
    print Dumper $DatacenterView;
    print Dumper $@;
    # On se déconnecte
    Util::disconnect();
    print "Disconnected \n";

    die('STOP ! Datacenter not found');
}
else
{
    print "Got Datacenter View\n";
}

# Recherche des datastore depuis la vue du datacentre

print "Find vm $vmName.\n";
<STDIN>;
my $VMview = '';
eval {
    $VMview  = Vim::find_entity_view(
        'view_type'    => 'VirtualMachine',
        'begin_entity' => $DatacenterView,
        'filter'        => { 'name'=> $vmName },
        'properties'    => [ qw/name summary parent resourceConfig/ ],
    );
};
if($@)
{
    print "Failed get VMview\n";
    print Dumper $VMview;
    print Dumper $@;
    die('STOP ! Failed get VMview');
}
print Dumper $VMview->{'summary'};
# On se déconnecte
Util::disconnect();
print "Disconnected \n";

print "End \n";
exit;


sub getContext
{
    my $result = '';
    my $ret = open(OUTPUT, "cat /root/scripts/.context |");
    if(not $ret)
    {
        die("Cannot open pipe", $!);
    }
    else
    {
        while(my $res = <OUTPUT>)
        {
            $result .= $res;
        }
        close OUTPUT;
    }

    my $hashContext = {};
    eval {
        $hashContext = JSON::decode_json($result);
    };
    if($@)
    {
        die "JSON::decode_json : $@";
    }

    if(ref $hashContext ne 'HASH')
    {
        die('Error on decode_json');
    }
    return $hashContext;
}

