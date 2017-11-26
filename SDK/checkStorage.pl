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



#exit;

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
#<STDIN>;
print "Connected \n";

my $threshold = 5;
#
# [ Action!!!  ]
#

my $DatacenterView = '';

# Chargement de la vue du datacentre

print "Find datacenter view.\n";
#<STDIN>;
eval{
    $DatacenterView  = Vim::find_entity_view(
        'view_type'     => 'Datacenter', 
        'filter'        => {'name'=> $context->{'datacenterName'}},
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

print "Find datastores views.\n";
#<STDIN>;
my $Datastores = '';
eval {
    $Datastores  = Vim::find_entity_views(
        'view_type'    => 'Datastore',
        'begin_entity' => $DatacenterView,
        'filter'        => {'name'=> qr/^pcc-[0-9]{6}$/},
        'properties'    => [ qw/name summary parent/ ],
    );
};
if($@)
{
    print "Failed to get Datastores\n";
    print Dumper $Datastores;
    print Dumper $@;
    die('STOP ! Failed to get Datastores');
}

if(not scalar @{$Datastores})
{
    print "Datastores not found\n";

    # On se déconnecte
    Util::disconnect();
    print "Disconnected \n";
    exit;
}

my @taskId         = ();
my $totalRation     = 0;
my $totalDatastore  = 0;
foreach my $DatastoreView (@{$Datastores})
{
    my $datastoreName = $DatastoreView->{'name'};

    my $ParentFolderView = '';
    eval {
        $ParentFolderView = Vim::get_view(
            'mo_ref'        => $DatastoreView->{'parent'},
            'properties'    => [ 'name' ],
        );
    };
    if($@)
    {
        print "Failed to load parent view\n";
        print Dumper $@;
        # On se déconnecte
        Util::disconnect();
        print "Disconnected \n";
        die('STOP ! Failed to get parent view');
    }

    my $folderName = $ParentFolderView->{'name'};

    # On verifie le nom du datastore
    if($folderName eq 'Shared Storages' )
    {
        print "Working on datastore \"$datastoreName\" ...\n";
#        <STDIN>;
    }
    else
    {
        print "Next datastore because \"$datastoreName\" not shared storage ($folderName).\n";
        next;
    }

    my $total           = sprintf("%.0f", $DatastoreView->{'summary'}->{'capacity'} / 1024 / 1024  / 1024 );
    my $used            = sprintf("%.0f", ( $DatastoreView->{'summary'}->{'capacity'} - $DatastoreView->{'summary'}->{'freeSpace'} ) / 1024 / 1024 / 1024 );
    my $provisionned    = sprintf("%.0f", ( $DatastoreView->{'summary'}->{'capacity'} - $DatastoreView->{'summary'}->{'freeSpace'}  + $DatastoreView->{'summary'}->{'uncommitted'} ) / 1024 / 1024/ 1024 );

    my $datastoreStatus = {
        'name'              => $datastoreName,
        'capacity'          => $total,
        'used'              => $used,
        'provisionned'      => $provisionned,
    };

    print "INFO \"$DatastoreView->{'name'}\" : ";
    print Dumper $datastoreStatus;

    # Calcul en %
    my $usageRatio        = int( 100 * $datastoreStatus->{'used'}         / $datastoreStatus->{'capacity'} );
    my $provisionnedRatio = int( 100 * $datastoreStatus->{'provisionned'} / $datastoreStatus->{'capacity'} );
    print "Datastore '$datastoreName' has : capacity=".$datastoreStatus->{'capacity'}." GB & used=$usageRatio% & provisionned=$provisionnedRatio% \n";

    $totalRation = $totalRation + $usageRatio;
    $totalDatastore++;
}

my $globalRation = $totalRation / $totalDatastore;
print "My global ration $globalRation%\n";
#<STDIN>;
if($globalRation >= $threshold)
{
    # https://www.ovh.com/fr/g934.premiers-pas-avec-l-api
    # Lancement du script API pour la command d'un nouveau filer.
    print "Launch order for new filer\n";

    my $infoDatacenter = startScriptOvhApiScript(action => 'orderFiler');
    print $infoDatacenter;

    push @taskId , $infoDatacenter;
}

if(scalar @taskId)
{
    print "List order : ";
    print Dumper \@taskId;
}
else
{
    print "Order not necessary\n";
}
# On se déconnecte
Util::disconnect();
print "Disconnected \n";

print "End \n";

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

sub startScriptOvhApiScript
{
    my (%params) = @_;
    my $action = $params{'action'};

    my $result = '';
    my $ret = open(OUTPUT, "perl /root/scripts/ovhApi.pl $action|");
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
    return $result;
}

