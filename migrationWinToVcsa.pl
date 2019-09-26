#!/usr/bin/perl

use strict;
use warnings;
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

use Data::Dumper;
use Getopt::Long qw(:config no_auto_abbrev);

my $login = getlogin();
my $libPath = "/home/$login";

# Sources : https://github.com/virtual-dark/common
require lib;
lib->import( $libPath );
require common::Logger;
require common::Result;
use File::Basename;
my $currentScriptName = basename($0);

# Sources : https://github.com/virtual-dark/VMware-Pub
my $vmwarelib = $libPath.'/VMware-Pub/SDK/lib';
lib->import( $vmwarelib );
require VMware::VIRuntime;

# apt-get install libssl-dev libcrypt-openssl-x509-perl libdatetime-perl libtime-duration-parse-perl libuniversal-require-perl
my $standaloneLib = $libPath.'/standaloneLib';
lib->import( $standaloneLib );

use JSON;
use Encode;

my $whatMagicIsDoneHere = "This script is an example script to automate win to vcsa migration actions \nExample : perl /home/github/VMware-Pub/migrationWinToVcsa.pl --contextFile /home/github/no_depot/VMUG/LABs/migrateWinToVcsa/env_migration_win_to_vcsa --actions getVcenterBuildForProvider --dryRun 1"; ## printed by --help

my @checkAndPrepare     = (qw/getVcenterBuildForVcMigration createSnapshot certsValidity unregisterExtensionVUM deleteComputerOnAD checkServices/);
my @runtime             = (qw/generateJson startAssistantMigration checkVcsaBin launchVerifyMigration launchMigration getVcenterBuildForVcMigration/);
my @migrateFullActions  = (@checkAndPrepare,@runtime);
my @actionsIsolated     = (qw/monitoAssistantMigration mountIsoFile monitoVerifyMigration monitoMigration getVcenterBuildForProvider /);
my $helpAction          = ' List Actions :
        checkAndPrepare     ==> '.join(", ",@checkAndPrepare).'
        runtime             ==> '.join(", ",@runtime).'
        migrateFullActions  ==> '.join(", ",@migrateFullActions).'
        actionsIsolated     ==> '.join(", ",@actionsIsolated);
# create your parameters variables 
my ( $contextFile, $actions, $doDryRun, $debug );
my $logFileGuestOp = 'C:\guestOp.log';
our  %PARAMS    = (
    'contextFile'  => {
        mandatory   => 1,
        string      => 1,
        help        => 'Gave the path of your context file',
        target      => \$contextFile,
    },
    'actions'   => {
        mandatory   => 1,
        string      => 1,
        help        => $helpAction,
        target      => \$actions,
    },
    'dryRun'          => {
        mandatory   => 0,
        string      => 1,
        help        => 'Specify this to DO NOT dryRun',
        target      => \$doDryRun,
    },
    'debug'          => {
        mandatory   => 0,
        string      => 1,
        help        => 'For enable debug mode',
        target      => \$debug,
    },
);

my $dryRun = 1;

################################
#   YOU CODE SHOULD BE HERE
################################

sub doIt
{
    my ($commonScriptObject, %params) = @_;

    Logger::info('Checking of context...');
    my $fnret = checkArguments( 
        'arguments' => [ qw/
            provider_server
            provider_username
            provider_password
            ssoUserFull
            ssoPassword
            datacenterName
            vCenterName
            vCenterIp
            vCenterWebPort
            vCenterOsUser
            vCenterOsPassword
            /
        ] 
    );
    not $fnret and return $fnret;
    Logger::log('Context Ok!!!');

    if(defined $doDryRun)
    {
        $dryRun = $doDryRun;
    }

    my @executeActions = ();
    if($actions eq 'checkAndPrepare')
    {
        @executeActions = @checkAndPrepare;
    }
    elsif($actions eq 'runtime')
    {
        @executeActions = @runtime;
    }
    elsif($actions eq 'migrateFullActions')
    {
        @executeActions = @migrateFullActions;
    }
    else
    {
        my @allActions = (@migrateFullActions,@actionsIsolated);
        if(not grep { $_ eq $actions } @allActions)
        {
            Logger::warn('This action('.$actions.') does not exist, the complete list of actions ==>', \@allActions);
            return Result->INTERNAL_ERROR('This action('.$actions.') does not exist');
        }
        @executeActions = ($actions);
    }

    Logger::log('List of actions that will be run :'."\n        - ".join ("\n        - ",@executeActions));
    not $dryRun and Logger::log('/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ DryRun Mode is Disabled /!\/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\/!\ ');
    $dryRun and Logger::log('DryRun Mode is Enabled');
    $fnret = promptValidation();
    not $fnret and return $fnret;

    foreach my $execAction (@executeActions)
    {
        no strict 'refs';
        require Carp;
        local $SIG{__DIE__} = \&Carp::confess;
        Logger::log('========================================> Execute action : '. $execAction.' <========================================');
        $fnret = &$execAction();
        not $fnret and return $fnret;
    }

    Logger::info('All actions are successfully'."\n        - ".join ("\n        - ",@executeActions));
    return Result->ok();
}

sub getVcenterBuildForProvider
{
    return getVcenterAbout( 'connectTo' => 'provider' );
}

sub getVcenterBuildForVcMigration
{
    my $try = 10;
    while ($try > 0)
    {
        my $fnret =  getVcenterAbout( 'connectTo' => 'vcMigration' );
        if(not $fnret)
        {
            Logger::warn('Failed to execute method "getVcenterAbout"',$fnret);
            waiting( timeout => 30 );
            $try -= 1;
            next;
        }
        return $fnret;
    }
    Logger::warn('Timeout!!!' );
    return Result->TIMEOUT();
}

sub getVcenterAbout
{
    my %params =  @_;
    my $connectTo   = $params{'connectTo'} || return Result->MISSING_PARAMETER('Missing param connectTo');

    my $connect = connectTovCenter( 'connectTo' => $connectTo );
    not $connect and return $connect;

    my $ServiceContent = Vim::get_service_content();
    my $about = $ServiceContent->about;

    disconnectFromvCenter();
    Logger::info('Build '.$connectTo.' ==> ',$about);
    return Result->ok($about);
}

sub launchMigration
{
    my $fnret = checkArguments( 'arguments' => [ qw/ mountPath vcsaBin jsonPath jsonFile logDirMigration provider_server / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $mountPath       = $context->{'mountPath'};
    my $vcsaBin         = $context->{'vcsaBin'};
    my $jsonPath        = $context->{'jsonPath'};
    my $jsonFile        = $context->{'jsonFile'};
    my $logDirMigration = $context->{'logDirMigration'};
    my $providerServer  = $context->{'provider_server'};

    $fnret = getThumbprint( 
        'host'  => $providerServer,
        'port'  => 443,
    );
    not $fnret and return $fnret;
    my $targetThumbprint = $fnret->value;

    my $cmd =   '/usr/bin/nohup '.$mountPath.$vcsaBin;
    $cmd .=     ' migrate --accept-eula '.$jsonPath.$jsonFile;
    $cmd .=     ' --deployment-target-ssl-thumbprint "'.$targetThumbprint.'"';
    $cmd .=     ' --log-dir '.$logDirMigration.' > /dev/null &';

    Logger::info('CMD : '. $cmd);

    if(not $dryRun)
    {
        if(not -d $logDirMigration)
        {
            $fnret = executeCmdOnLocalHost( 'cmd'   => 'mkdir -p '.$logDirMigration );
            not $fnret and return $fnret;
        }
        else
        {
            $fnret = executeCmdOnLocalHost( 'cmd'   => 'rm -rf '.$logDirMigration.'/*' );
            not $fnret and return $fnret;
        }
        $fnret = executeCmdOnLocalHost( 'cmd'   => $cmd );
        not $fnret and return $fnret;
    }
    Logger::info('Migration started');
    if(not $dryRun)
    {
        Logger::info('Start monitoring of process');
        $fnret = monitoMigration();
        not $fnret and return $fnret;
    }
    return Result->ok();
}

sub launchVerifyMigration
{
    my $fnret = checkArguments( 'arguments' => [ qw/ mountPath vcsaBin jsonPath jsonFile logDirVerify provider_server / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $mountPath       = $context->{'mountPath'};
    my $vcsaBin         = $context->{'vcsaBin'};
    my $jsonPath        = $context->{'jsonPath'};
    my $jsonFile        = $context->{'jsonFile'};
    my $logDirVerify    = $context->{'logDirVerify'};
    my $providerServer  = $context->{'provider_server'};

    $fnret = getThumbprint( 
        'host'  => $providerServer,
        'port'  => 443,
    );
    not $fnret and return $fnret;
    my $targetThumbprint = $fnret->value;

    my $cmd =   '/usr/bin/nohup '.$mountPath.$vcsaBin;
    $cmd .=     ' migrate --precheck-only '.$jsonPath.$jsonFile;
    $cmd .=     ' --deployment-target-ssl-thumbprint "'.$targetThumbprint.'"';
    $cmd .=     ' --log-dir '.$logDirVerify.' > /dev/null &';

    Logger::info('CMD : '. $cmd);
    
    if(not $dryRun)
    {
        if(not -d $logDirVerify)
        {
            $fnret = executeCmdOnLocalHost( 'cmd'   => 'mkdir -p '.$logDirVerify );
            not $fnret and return $fnret;
        }
        else
        {
            $fnret = executeCmdOnLocalHost( 'cmd'   => 'rm -rf '.$logDirVerify.'/*' );
            not $fnret and return $fnret;
        }

        $fnret = executeCmdOnLocalHost( 'cmd'   => $cmd );
        not $fnret and return $fnret;
    }
    Logger::info('Verify started');
    if(not $dryRun)
    {
        Logger::info('Start monitoring of process');
        $fnret = monitoVerifyMigration();
        not $fnret and return $fnret;
    }
    return Result->ok();
}

sub monitoVerifyMigration
{
    my $fnret = checkArguments( 'arguments' => [ qw/ logDirVerify / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    return monitoProcess( 'logDir' => $context->{'logDirVerify'} );
}

sub monitoMigration
{
    my $fnret = checkArguments( 'arguments' => [ qw/ logDirMigration / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    return monitoProcess( 'logDir' => $context->{'logDirMigration'} );
}

sub monitoProcess
{
    my %params  = @_;
    my $logDir  =  $params{'logDir'} || return Result->MISSING_PARAMETER('Missing logDir');
    
    my $installStatus = '';
    my $try = 1080;
    while ($try > 0)
    {
        my $fnret = decodeJsonFile(
            'jsonPath'  => $logDir,
            'jsonFile'  => 'vcsa-cli-installer.json',
        );
        if(not $fnret and $fnret->status == 210)
        {
            Logger::info('Pending log file');
        }
        elsif(not $fnret)
        {
            return $fnret;
        }
        else
        {
            $installStatus = $fnret->value;
            if($installStatus->{'status'} eq 'success')
            {
                Logger::info('Success !!!', $installStatus);
                return Result->ok($installStatus);
            }
            elsif($installStatus->{'status'} =~ /error/i)
            {
                Logger::critical('Failed !!!',$installStatus);
                Logger::warn('Check file --> '.$logDir.'vcsa-cli-installer.log <-- for more informations');
                return Result->INTERNAL_ERROR();
            }
            else
            {
                Logger::info('Action in progress...',$installStatus);
            }
        }
        waiting( timeout => 4 );
        $try -= 1;
    }
    Logger::warn('Timeout!!! last result ==> ',$installStatus );
    return Result->TIMEOUT();
}

sub getThumbprint
{
    my %params  = @_;
    my $host    =  $params{'host'} || return Result->MISSING_PARAMETER('Missing host');
    my $port    =  $params{'port'} || return Result->MISSING_PARAMETER('Missing port');

    my $cmd = 'openssl s_client -connect '.$host.':'.$port.' < /dev/null 2>/dev/null | openssl x509 -fingerprint -noout -in /dev/stdin';
    my $fnret = executeCmdOnLocalHost(
        cmd => $cmd
    );
    not $fnret and return $fnret;
    my $result = $fnret->value;

    chomp($result);
    Logger::info('openssl -fingerprint : ',$result);
    if($result =~ /^SHA\d+ Fingerprint=([0-9a-zA-Z:]+)/)
    {
        my $thumbprint = $1;
        Logger::info('Thumbprint : '.$thumbprint);
        return Result->ok($thumbprint);
    }
    return Result->NOT_FOUND('Thumbprint Not Found');
}

sub startAssistantMigration
{
    my $fnret = checkArguments( 'arguments' => [ qw/ migrationAssistant ssoPassword vCenterIp/ ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $migrationAssistant  = $context->{'migrationAssistant'};
    my $ssoPassword         = $context->{'ssoPassword'};
    my $vCenterIp           = $context->{'vCenterIp'};

    $fnret = executeCmdInGuest(
        'programPath'   => 'C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe',
        'cmd'           => 'Test-Path -Path '.$migrationAssistant,
    );
    not $fnret and return $fnret;

    waiting('timeout' => 2);
    $fnret = getLogFromvCenter();
    not $fnret and return $fnret;
    my $content = $fnret->value;

    if($content !~ /True/)
    {
        Logger::critical('Migration wizard not found ('.$migrationAssistant.')');
        return Result->NOT_FOUND();
    }

    $dryRun and return Result->ok();
    $fnret = executeCmdInGuest(
        'programPath'   => $migrationAssistant,
        'cmd'           => '--admin_password '.$ssoPassword.' -i '.$vCenterIp,
        'noRedirect'    => 1,
    );
    not $fnret and return $fnret;

    return monitoAssistantMigration();
}

sub monitoAssistantMigration
{
    waiting('timeout' => 2);

    my $try = 40;
    while ($try > 0)
    {
        my $fnret = getLogFromvCenter('guestFilePath' => 'C:\Users\Administrator\AppData\Local\Temp\vcsMigration\UpgradeRunner.log' );
        if(not $fnret and ($fnret->status == 212 or $fnret->status == 210))
        {
            Logger::info('Pending log file');
        }
        elsif(not $fnret)
        { 
            return $fnret;
        }
        else
        {
            my $content = $fnret->value;
            if($content =~ /Distributed upgrade mode 'requirements' completed successfully/i)
            {
                Logger::info('Assistant migration started!');
                return Result->ok();
            }
            Logger::info('Wait for the migration wizard to start',$content);
        }
        waiting(timeout=>2);
        $try -= 1;
    }
    Logger::info('Assistant migration not start... Timeout!');
    return Result->TIMEOUT();
}


sub checkVcsaBin
{
    my $fnret = checkArguments( 'arguments' => [ qw/ isoFile isoPath mountPath / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $isoFile         = $context->{'isoFile'};
    my $isoPath         = $context->{'isoPath'};
    my $mountPath       = $context->{'mountPath'};
    my $vcsaBin         = $context->{'vcsaBin'};

    $fnret = executeCmdOnLocalHost( 'cmd'   => 'df' );
    not $fnret and return $fnret;
    my $result = $fnret->value;
    
    my $mntTest = $mountPath;
    chop($mntTest);

    if($result !~ /$mntTest/)
    {
        Logger::critical($mntTest .' unmounted',$result);
        Logger::warn('Use the mountIsoFile action to mount the ISO on your system');
        return Result->NOT_FOUND($mntTest .' unmounted');
    }

    Logger::info($mountPath.' is already mounted');
    if( not -e $mountPath.$vcsaBin)
    {
        Logger::critical('vcsaBin not found');
        return Result->INTERNAL_ERROR();
    }

    $fnret = executeCmdOnLocalHost( 'cmd'   => $mountPath.$vcsaBin.' --help' );
    not $fnret and return $fnret;
    $result = $fnret->value;

    if($result !~ /Available sub-commands\. Use vcsa-deploy/)
    {
        Logger::critical($vcsaBin .' does not return the right message',$result);
        return Result->INTERNAL_ERROR($vcsaBin .' does not return the right message');
    }
    Logger::info('Vcsa bin ('.$mountPath.$vcsaBin.') is OK!');
    return Result->ok();
}

sub mountIsoFile
{
    my $fnret = checkArguments( 'arguments' => [ qw/ isoFile isoPath mountPath / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $isoFile         = $context->{'isoFile'};
    my $isoPath         = $context->{'isoPath'};
    my $mountPath       = $context->{'mountPath'};
    my $vcsaBin         = $context->{'vcsaBin'};

    my $cmd = sprintf('mount -o loop -t iso9660 %s%s %s',$isoPath,$isoFile,$mountPath);
    Logger::info('CMD : '. $cmd);
    $fnret = executeCmdOnLocalHost( 'cmd'   => $cmd );
    if(not $fnret and $fnret->msg =~ /(is write-protected, mounting read-only|is already mounted)/)
    {
        return Result->ok();
    }
    elsif(not $fnret)
    {
        return $fnret;
    }
    return Result->ok();
}
#### JSON

sub generateJson
{
    my $fnret = checkArguments( 
        'arguments' => [ 
            qw/vCenterIp ssoUser ssoDomain_name ssoPassword provider_server provider_username provider_password portgroupName datacenterName
            datastore clusterName vCenterWebPort vmFolder deploymentOption vcsaName ipFamily ipMode temporary_vCenterIp
            dnsServer networkPrefix networkGw osVcsaPassword/
        ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;
 
    my $sep = '.';   
    my $hashConfig = {
        '__version'         => '2.3.0',
        '__comments'        => 'Demo template to deploy a vCenter Server Appliance with an embedded Platform Services Controller',
        'source'.$sep.'vc'  => {
            'description'       => {
                '__comments'        => [
                    "This section describes the source Windows vCenter that you want to migrate.",
                    "For vCenter running on a virtual machine, you can automate the installation and launching of",
                    "the Migration Assistant by including the 'run.migration.assistant' section.",
                    "For vCenter running on a physical machine, or if you are running Migration Assistant manually",
                    "on the Windows vCenter, copy and paste the thumbprint value from the Migration Assistant",
                    "console output on the source vCenter to the 'migration.ssl.thumbprint' key in the 'vc.win'",
                    "section, and remove the 'run.migration.assistant' section. You can read more about",
                    "'migration.ssl.thumbprint' in template help, i.e. vcsa-deploy migrate --template-help"
                ],
            },
            'vc'.$sep.'win'     => {
                'hostname'          => $context->{'vCenterIp'},
                'username'          => $context->{'ssoUser'}.'@'.$context->{'ssoDomain_name'},
                'password'          => $context->{'ssoPassword'},
            },
        },
        'new'.$sep.'vcsa'   => {
            'vc'                => {
                'hostname'                  => $context->{'provider_server'},       # "<FQDN or IP address of the vCenter Server instance>"
                'username'                  => $context->{'provider_username'},     # "<The user name of a user with administrative privileges or the Single Sign-On administrator on vCenter.>"
                'password'                  => $context->{'provider_password'},     # "<The password of a user with administrative privileges or the Single Sign-On administrator on vCenter.>"
                'deployment'.$sep.'network' => $context->{'portgroupName'},     
                'datacenter'                => [ $context->{'datacenterName'} ],    # ["parent folder","child folder","Datacenter"]
                'datastore'                 => $context->{'datastore'},             # "<A specific ESXi host or DRS cluster datastore, or a specific datastore in a datastore cluster.>"
                'target'                    => [ $context->{'clusterName'} ],       # ["parent folder","child folder","<ESXi host or DRS cluster>"]
                'port'                      => $context->{'vCenterWebPort'},        # The HTTPS reverse proxy port of the target vCenter Server instance.
                'vm'.$sep.'folder'          => $context->{'vmFolder'},
            },
            'appliance'         => {
                'thin'.$sep.'disk'.$sep.'mode'      => JSON::true,
                'deployment'.$sep.'option'          => $context->{'deploymentOption'},
                'name'                              => $context->{'vcsaName'},      # vcenterName
            },
            'temporary'.$sep.'network'  => {
                'ip'.$sep.'family'          => $context->{'ipFamily'},              # ipv4 or ipv6
                'mode'                      => $context->{'ipMode'},                # static or dhcp
                'ip'                        => $context->{'temporary_vCenterIp'},   # "<Static IP address. Remove this if using dhcp.>"
                'dns'.$sep.'servers'        => [ $context->{'dnsServer'} ],         # "<DNS Server IP Address. Remove this if using dhcp.>"
                'prefix'                    => $context->{'networkPrefix'},         #
                'gateway'                   => $context->{'networkGw'},             # "<Gateway IP address. Remove this if using dhcp.>"
                'system'.$sep.'name'        => $context->{'vCenterIp'},             # "<FQDN or IP address for the appliance. Remove this if using dhcp.>"
            },
            'os'                => {
                'password'                              => $context->{'osVcsaPassword'},  # "<Appliance root password.>"
                'ssh'.$sep.'enable'                     => JSON::true,# false or true
            },
            'ovftool'.$sep.'arguments' => {
                'prop:guestinfo.cis.appliance.root.shell' => '/bin/bash',
            },
            'user-options'      => {
                'vcdb'.$sep.'migrateSet'    => 'core',
            },
        },
        'ceip'      => {
           'description'    => {
               '__comments'         => [
                   "++++VMware Customer Experience Improvement Program (CEIP)++++",
                   "VMware's Customer Experience Improvement Program (CEIP) ",
                   "provides VMware with information that enables VMware to ",
                   "improve its products and services, to fix problems, ",
                   "and to advise you on how best to deploy and use our ",
                   "products. As part of CEIP, VMware collects technical ",
                   "information about your organization's use of VMware ",
                   "products and services on a regular basis in association ",
                   "with your organization's VMware license key(s). This ",
                   "information does not personally identify any individual. ",
                   "",
                   "Additional information regarding the data collected ",
                   "through CEIP and the purposes for which it is used by ",
                   "VMware is set forth in the Trust & Assurance Center at ",
                   "http://www.vmware.com/trustvmware/ceip.html . If you ",
                   "prefer not to participate in VMware's CEIP for this ",
                   "product, you should disable CEIP by setting ",
                   "'ceip.enabled': false. You may join or leave VMware's ",
                   "CEIP for this product at any time. Please confirm your ",
                   "acknowledgement by passing in the parameter ",
                   "--acknowledge-ceip in the command line.",
                   "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++",
               ],
           },
           'settings'       => {
               'ceip'.$sep.'enabled'       => JSON::false, # true or false
           },
        },
    };
    my $json_pretty = JSON->new->pretty->utf8->encode($hashConfig);
    my $jsonLog = $json_pretty;
    $jsonLog =~ s/"password" : "[0-9a-zA-Z!@#$%]{4,}"/"password" : "xxxxxxxxx"/gi;
    Logger::info('json',$jsonLog);

    if(not -d $context->{'jsonPath'})
    {
        return _stopBecauseFailed('msg' => 'No such directory '.$context->{'jsonPath'});
    }

    my $fullJsonFile = $context->{'jsonPath'}.$context->{'jsonFile'};
    my $FILEJSON = undef;
    if(open($FILEJSON, '>', $fullJsonFile))
    {
        print $FILEJSON $json_pretty;
        close($FILEJSON);
    }
    else
    {
        return _stopBecauseFailed('msg' => 'Files: failed to execute open file : '.$fullJsonFile, 'error' => $FILEJSON);
    }

    if( not -e $fullJsonFile )
    {
        return _stopBecauseFailed('msg' => sprintf('Files: MISSING RESULT, fullJsonFile (%s) not exists.',$fullJsonFile), 'error' => $FILEJSON);
    }
    Logger::info('JSON Generated ==> '.$fullJsonFile);
    return Result->ok($hashConfig);
}

#### CHECK AND PREPARE 
sub createSnapshot
{
    my $connect = connectTovCenter( 'connectTo' => 'provider' );
    not $connect and return $connect;

    my $fnret = loadVcenterVmView();
    not $fnret and return $fnret;
    my $VMView = $fnret->value;

    my $Task = '';
    eval{
        $Task = $VMView->CreateSnapshot_Task(
            'name'        => 'BeforeMigration',
            'description' => 'Snapshot before migration win to vcsa',
            'memory'      => 'false',
            'quiesce'     => 'false',
        );
    };
    $@ and return _stopBecauseFailed('msg' => 'Fail to snapshot', 'error' => $@);
    
    Logger::info('Snapshot started', $Task);
    return disconnectFromvCenter();
}

sub certsValidity
{
    my $fnret = checkArguments( 'arguments' => [ qw/ vCenterIp vCenterWebPort / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    require Net::SSL::ExpireDate;
    my $ed = '';
    eval{
        $ed = Net::SSL::ExpireDate->new( https => $context->{'vCenterIp'}.':'.$context->{'vCenterWebPort'} );
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to check Expiration date', 'error' => $@);

    if (defined $ed->expire_date)
    {
        Logger::info('EndDateCert : '.$ed->expire_date);
        if($ed->is_expired)
        {
            Logger::critical('Certificate is expired!!!!!!!');
            return Result->ACTION_IMPOSSIBLE();
        }

        if($ed->is_expired(DateTime::Duration->new(months => 2)))
        {
            Logger::critical('Attention your certificates expire in less than 2 months');
            $fnret = promptValidation();
            not $fnret and return $fnret;
        }
        return Result->ok();
    }
    return Result->INTERNAL_ERROR();
}

sub unregisterExtensionVUM
{
    my %params = @_;

    my $connect = connectTovCenter( 'connectTo' => 'vcMigration' );
    not $connect and return $connect;

    my $ExtensionManagerView = Vim::get_view('mo_ref' => Vim::get_service_content()->extensionManager);
    
    my $Extension = '';
    eval{
        $Extension =  $ExtensionManagerView->FindExtension( extensionKey => 'com.vmware.vcIntegrity' );
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to FindExtension!!!', 'error' => $@);

    if(not $Extension)
    {
        Logger::info('Extension not found');
        return Result->ok();
    }
    Logger::info('Extension found : '.$Extension->description->label);
    eval{
        not $dryRun and $ExtensionManagerView->UnregisterExtension( 'extensionKey' => 'com.vmware.vcIntegrity' );
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to UnregisterExtension!!!', 'error' => $@);

    disconnectFromvCenter();
    return Result->ok();
}

sub deleteComputerOnAD
{
    my $fnret = getContext();
    not $fnret and return $fnret;
    my $context = $fnret->value;
    
    my $domain          = $context->{'domain'};
    my $computerName    = $context->{'vCenterOsComputerName'};
    my $userDomain      = $context->{'userDomain'};
    my $passwordDomain  = $context->{'passwordDomain'};


    if(not $domain or not $computerName or not $userDomain or not $passwordDomain)
    {
        Logger::info('Function disabled');
        return Result->ok();
    }
    $fnret = executeCmdInGuest(
        'programPath'   => 'C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe',
        'cmd'           => 'SYSTEMINFO',
    );
    not $fnret and return $fnret;

    waiting(timeout=>10);
    $fnret = getLogFromvCenter();
    not $fnret and return $fnret;
    my $content = $fnret->value;

    if($content !~ /$domain/)
    {
        Logger::info('Already remove on Domain('.$domain.')');
        return Result->ok();
    }

    $fnret = executeCmdInGuest(
        'programPath'   => 'C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe',
        'cmd'           => 'CMD.EXE /C \'NETDOM REMOVE '.$computerName.' /Domain:'.$domain.' /userD:'.$userDomain.' /passwordD:'.$passwordDomain.'\'',
    );
    not $fnret and return $fnret;

    waiting(timeout=>4);
    $fnret = getLogFromvCenter();
    not $fnret and return $fnret;
    $content = $fnret->value;

    if($content =~ /The command completed successfully/)
    {
        return Result->ok();
    }
    return Result->INTERNAL_ERROR();
}

sub checkServices
{
    my @services = (qw/VMTools vmware-cis-config VMWareAfdService rhttpproxy VMWareDirectoryService 
        VMWareCertificateService VMwareIdentityMgmtService VMwareSTS VMwareComponentManager 
        vmware-license vmwareServiceControlAgent vapiEndpoint invsvc vpxd EsxAgentManager
        vimPBSM vdcs vmsyslogcollector vmware-vpx-workflow VServiceManager vspherewebclientsvc
        vmware-perfcharts vmwarevws/);
    foreach my $service (@services)
    {
        my $fnret = executeCmdInGuest(
            'programPath'   => 'C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe',
            'cmd'           => 'Get-Service '.$service,
        );
        not $fnret and return $fnret;

        waiting(timeout=>2);
        $fnret = getLogFromvCenter();
        not $fnret and return $fnret;
        my $content = $fnret->value;

        if($content !~ /Running/i)
        {
            Logger::info('Service : '.$service.' not running ', $content);
            return Result->INTERNAL_ERROR();
        }
        Logger::info('Service '.$service.' UP');
    }

    return Result->ok();
}

sub _stopBecauseFailed
{
    my %params =  @_;

    my $error   = $params{'error'};
    my $msg     = $params{'msg'};
    
    disconnectFromvCenter();
    Logger::critical($msg, $error);
    return Result->INTERNAL_ERROR();
}


sub waiting
{
    my %params  = @_;
    my $timeout = $params{timeout} || 300;

    while ($timeout > 0)
    {
        Logger::log("Sleeping $timeout sec ...");
        sleep 2;
        $timeout -= 2;
    }

    return Result->ok();
}

sub getLogFromvCenter
{
    my %params =  @_;

    my $guestFilePath   = $params{'guestFilePath'} || $logFileGuestOp;

    my $fnret = checkArguments( 'arguments' => [ qw/ vCenterOsUser vCenterOsPassword / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $connect = connectTovCenter( 'connectTo' => 'provider' );
    not $connect and return $connect;

    $fnret = loadVcenterVmView();
    not $fnret and return $fnret;
    my $VMView = $fnret->value;

    my $powerState = $VMView->{'runtime.powerState'};
    if( $powerState->{'val'} ne 'poweredOn' )
    {
        Logger::critical( 'The vm need to be poweredOn' );
        disconnectFromvCenter();
        return Result->ACTION_IMPOSSIBLE();
    }

    my $auth = NamePasswordAuthentication->new(
        'username'              => $context->{'vCenterOsUser'},
        'password'              => $context->{'vCenterOsPassword'},
        'interactiveSession'    => 'false',
    );

    my $GuestOperationsManagerView = '';
    eval{
        $GuestOperationsManagerView = Vim::get_view('mo_ref' => Vim::get_service_content()->guestOperationsManager);
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to load guestOperationsManager', 'error' => $@);

    my $FileManager = '';
    eval{
        $FileManager = Vim::get_view('mo_ref' => $GuestOperationsManagerView->fileManager);
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to load fileManager', 'error' => $@);

    Logger::log('InitiateFileTransferFromGuest on '.$VMView->{'name'}.' --> "'.$guestFilePath.'" <-- ');

    my $FileTransferFromGuest = '';
    eval{
        $FileTransferFromGuest = $FileManager->InitiateFileTransferFromGuest(
            'auth'          => $auth,
            'vm'            => $VMView,
            'guestFilePath' => $guestFilePath,
        );
    };
    if($@)
    {
        if(ref($@) eq 'SoapFault' and $@->{'name'} eq 'FileNotFoundFault')
        {
            Logger::warn($@->{'fault_string'});
            return Result->NOT_FOUND($@->{'fault_string'});
        }
        return _stopBecauseFailed('msg' => 'Failed to initiate file transfert', 'error' => $@);
    }

    Logger::info('Result FileTransferFromGuest : ',$FileTransferFromGuest);
    my $url = $FileTransferFromGuest->url.'';
    disconnectFromvCenter();
    Logger::log('Url --> ', $url);


    require LWP::UserAgent;

    my $content = '';
    eval{
        my $ua = new LWP::UserAgent;
        $ua->timeout(120);
        my $request = new HTTP::Request('GET', $url);
        my $response = $ua->request($request);
        $content = $response->content();
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to get content file', 'error' => $@);

    if(not $content)
    {
        Logger::critical('Empty file');
        return Result->NO_CHANGE();
    }
    my @allLines = split("\n",$content);
    
    my $contentFormat  = '';
    foreach my $line (@allLines)
    {
        chomp($line);
        $line = encode('utf8',$line);
        $contentFormat .= $line."\n";
    }

    Logger::info('Content', $contentFormat);
    return Result->ok($contentFormat);
}

sub executeCmdInGuest
{
    my %params  = @_;
    my $programPath      =  $params{'programPath'} || return Result->MISSING_PARAMETER('Missing programPath');
    my $cmd              =  $params{'cmd'} || return Result->MISSING_PARAMETER('Missing cmd');
    my $noRedirect       =  $params{'noRedirect'};

    if( $cmd !~ />|Out-File/ and not $noRedirect)
    {
#        $cmd .= ' > '.$logFileGuestOp.' 2>&1';
        $cmd .= ' 2>&1 | Out-File -FilePath '.$logFileGuestOp.' -Encoding utf8'
    }

    my $fnret = checkArguments( 'arguments' => [ qw/ vCenterOsUser vCenterOsPassword / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $connect = connectTovCenter( 'connectTo' => 'provider' );
    not $connect and return $connect;

    $fnret = loadVcenterVmView();
    not $fnret and return $fnret;
    my $VMView = $fnret->value;

    my $powerState = $VMView->{'runtime.powerState'};
    if( $powerState->{'val'} ne 'poweredOn' )
    {
        Logger::critical( 'The vm need to be poweredOn' );
        disconnectFromvCenter();
        return Result->ACTION_IMPOSSIBLE();
    }

    my $auth = NamePasswordAuthentication->new(
        'username'              => $context->{'vCenterOsUser'},
        'password'              => $context->{'vCenterOsPassword'},
        'interactiveSession'    => 'false',
    );

    my $GuestOperationsManagerView = '';
    eval{
        $GuestOperationsManagerView = Vim::get_view('mo_ref' => Vim::get_service_content()->guestOperationsManager);
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to load guestOperationsManager', 'error' => $@);

    my $ProcessManagerView = '';
    eval{
        $ProcessManagerView = Vim::get_view('mo_ref' => $GuestOperationsManagerView->processManager);
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to load processManager', 'error' => $@);

    my $cmdSpec = GuestProgramSpec->new(
        'programPath'       => $programPath,
        'arguments'         => $cmd,
        'workingDirectory'  => undef,
    );
    if($debug)
    {
        Logger::info('StartProgramInGuest on '.$VMView->{'name'}.' --> "'.$programPath.'" <-- '.$cmd);
    }
    else
    {
        Logger::info('StartProgramInGuest on '.$VMView->{'name'}.' --> "'.$programPath.'" <-- ');
    }

    my $exec = '';
    eval{
        $exec = $ProcessManagerView->StartProgramInGuest(
            'auth'          => $auth,
            'vm'            => $VMView,
            'spec'          => $cmdSpec,
        );
    };

    Logger::info('Result exec : ',$exec);
    disconnectFromvCenter();
    return Result->ok($exec);
}

sub loadVcenterVmView
{
    my $fnret = checkArguments( 'arguments' => [ qw/ datacenterName vCenterName / ] );
    not $fnret and return $fnret;
    my $context = $fnret->value;

    my $DatacenterView = '';
    Logger::info('Find datacenter view');
    eval{
        $DatacenterView  = Vim::find_entity_view(
            'view_type'     => 'Datacenter',
            'filter'        => {'name'=> $context->{'datacenterName'}},
            'properties'    => ['name'],
        );
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed to get DatacenterView', 'error' => $@);
    Logger::info('Got Datacenter View');
    
    my $vmName = $context->{'vCenterName'};
    Logger::info('Find vm '.$vmName);
    my $VMview = '';
    eval {
        $VMview  = Vim::find_entity_view(
            'view_type'    => 'VirtualMachine',
            'begin_entity' => $DatacenterView,
            'filter'        => { 'name'=> $vmName },
            'properties'    => [ 'name', 'summary', 'runtime.powerState'  ],
        );
    };
    $@ and return _stopBecauseFailed('msg' => 'Failed get VMview', 'error' => $@);
    Logger::info('VM loaded ==> '.$VMview->{'name'});

    return Result->ok($VMview);
}

sub connectTovCenter
{
    my %params =  @_;

    my $connectTo   = $params{'connectTo'} || return Result->MISSING_PARAMETER('Missing param connectTo');

    if($connectTo !~ /^(provider|vcMigration)$/)
    {
        Logger::critical('Bad param connectTo, accept "provider" or "vcMigration"');
        return Result->INTERNAL_ERROR();
    }

    my $server      = '';
    my $username    = '';
    my $password    = '';
    if($connectTo eq 'provider')
    {
        my $fnret = checkArguments( 'arguments' => [ qw/ provider_server provider_username provider_password / ] );
        not $fnret and return $fnret;
        my $context = $fnret->value;

        $server      = $context->{'provider_server'};
        $username    = $context->{'provider_username'};
        $password    = $context->{'provider_password'};
    }
    else
    {
        my $fnret = checkArguments( 'arguments' => [ qw/ vCenterIp ssoUserFull ssoPassword / ] );
        not $fnret and return $fnret;
        my $context = $fnret->value;
        
        $server      = $context->{'vCenterIp'};
        $username    = $context->{'ssoUserFull'};
        $password    = $context->{'ssoPassword'};
    }


    eval{
        Opts::set_option('server', $server);
        Opts::set_option('username', $username);
        Opts::set_option('password', $password);
    };
    if($@)
    {
        Logger::critical('Failed to set option',$@);
        return Result->INTERNAL_ERROR();
    }

    Logger::log('Connecting ...');
    eval{
        Util::connect();
    };
    if($@)
    {
        Logger::critical('Failed to connect',$@);
        return Result->INTERNAL_ERROR();
    }
    Logger::log('Connected');
    return Result->ok();
}

sub disconnectFromvCenter
{
    eval{
        Util::disconnect();
    };
    if($@)
    {
        Logger::critical('Fail to disconnect',$@);
        return Result->INTERNAL_ERROR();
    }
    Logger::log('disconnected');
    return Result->ok();

}

sub executeCmdOnLocalHost
{
    my %params  = @_;
    my $cmd              =  $params{'cmd'} || return Result->MISSING_PARAMETER('Missing cmd');
    my $timeout          =  $params{'timeout'} || 60;

    if($timeout !~ /^\d+$/)
    {
        Logger::critical('Incorrect value for param timeout');
        return Result->INTERNAL_ERROR();
    }

    my $result  = '';
    my $retcode = 0;

    $cmd = $cmd.' 2>&1';
    Logger::info('CMD ==> '.$cmd);
    
    eval
    {
        local $SIG{ALRM} = sub 
        { 
            die 'Timeout Alarm';
        };
        alarm $timeout;

        my $ret = open(OUTPUT, "$cmd |");
        if(not $ret)
        {
            Logger::critical('Cannot open pipe', $!);
            return Result->INTERNAL_ERROR();
        }
        else
        {
            while(my $res = <OUTPUT>)
            {
                $result .= $res;
            }
            close OUTPUT;
            $retcode = $?;
        }

        alarm 0;
    };

    if ($@ and $@ =~ /Timeout Alarm/i)
    {
        Logger::critical('Timeout ('.$timeout.' s) expired during command execution', $result);
        return Result->TIMEOUT();
    }

    if($retcode != 0)
    {
        Logger::critical('Command wasn\'t executed properly, return code : '.$retcode.' ('.$result.')');
        return Result->INTERNAL_ERROR('Command wasn\'t executed properly, return code : '.$retcode.' ('.$result.')');
    }

    Logger::info('Command returned ('.$retcode.') : '.$result);
    return Result->ok($result);
}

sub checkArguments
{
    my %params  = @_;
    my $arguments   =  $params{'arguments'};

    not $arguments and return Result->MISSING_PARAMETER('MISSING param arguments');
    if(ref($arguments) ne 'ARRAY')
    {
        Logger::warn('arguments need to be an array ref',$arguments);
        return Result->INTERNAL_ERROR();
    }

    my $fnret = getContext();
    not $fnret and return $fnret;
    my $context = $fnret->value;

    foreach my $argument (@{$arguments})
    {
        if(not exists $context->{$argument})
        {
            Logger::warn('Missing key '.$argument);
            return Result->INTERNAL_ERROR();
        }

        if(not $context->{$argument})
        {
            Logger::warn('Missing value for key '.$argument);
            return Result->INTERNAL_ERROR();
        }
    }
    return Result->ok($context);
}

sub getContext
{
    return decodeJsonFile( 'jsonFile' => $contextFile );
}

sub decodeJsonFile
{
    my %params  = @_;
    my $jsonPath  = $params{'jsonPath'} || '';
    my $jsonFile  = $params{'jsonFile'} || return Result->MISSING_PARAMETER('Missing jsonFile');

    if( $jsonPath and not -d $jsonPath )
    {
        return _stopBecauseFailed('msg' => 'Files: INVALID_ARGUMENT, jsonPath ('.$jsonPath.') not is a directory.');
    }

    my $fullJsonPath = $jsonPath.$jsonFile;
    if( not -e $fullJsonPath )
    {
        Logger::critical('Files: INVALID_ARGUMENT, jsonFile ('.$jsonFile.' - '.$fullJsonPath.') not exists.');
        return Result->NOT_FOUND('Files: INVALID_ARGUMENT, jsonFile ('.$jsonFile.' - '.$fullJsonPath.') not exists.');
    }

    my $json = '';
    if(open FILEJSON, '<'.$fullJsonPath)
    {
        $json = do { local $/; <FILEJSON> };
    }
    else
    {
        return _stopBecauseFailed('msg' => 'Files: Failed open file '.$fullJsonPath, 'error' => $!);
    }

    my $data = {};
    eval{
        require JSON;
        binmode STDOUT, ":utf8";
        require utf8;

        $data = JSON::decode_json($json);
    };
    $@ and return _stopBecauseFailed('msg' => 'Data: Failed decode json '.$json, 'error' => $@);

    return Result->ok($data);
}

################################
#   / YOU CODE SHOULD BE HERE
################################

######### INTERNAL MAGIC nothing to do here. go to the main sub directly

sub main
{
    my $fnret = doIt(@_);
    not $fnret and Logger::critical($fnret);
    return $fnret;
}

sub promptValidation
{
    my (%params) = @_;

    my $valideOk = undef;
    Logger::log('valid info by "yes" ... Continue anyway ?');
    while (defined (my $returnKey = <STDIN>) and !defined  ($valideOk) )
    {
        chomp($returnKey);
        if($returnKey =~ /^yes$/i)
        {
            Logger::info("Validation Ok");
            return Result->ok("Validation Ok");
        }
        elsif($returnKey =~ /^no$/i)
        {
            Logger::warn("Validation NOk");
            return Result->NO_ANSWER("Validation NOk");
        }
        else
        {
            Logger::warn('Bad return => "' . $returnKey );
        }
    }
}

sub printHelpAndExit
{
    Logger::info("== Help ==");
    Logger::info("Usage   : $0");
    Logger::info('Feature : '.$whatMagicIsDoneHere);
    Logger::info("  --help                      : display this helps and exits");
    foreach my $ref (sort(keys %PARAMS))
    {
        my $msg="  --".$ref;
        if($PARAMS{$ref}->{'string'})
        {
            $msg .= '=value';
        }
        if(!$PARAMS{$ref}->{'mandatory'})
        {
            $msg .= '  (Opt)';
        }

        $msg .=(" " x (30- length($msg)>0?30- length($msg):0)).': '.$PARAMS{$ref}->{'help'};
        Logger::info($msg);
    }
    Logger::info("\n");
    exit 0;
}

### prepare getOpts
my %opts = ();

foreach my $ref (keys %PARAMS)
{
    my $vv = $ref;
    if($PARAMS{$ref}->{'string'} and $PARAMS{$ref}->{'string'} == 1)
    {
        $vv = $vv.'=s';
    }
    $opts{$vv} = $PARAMS{$ref}->{'target'};
}

my $result_opts = GetOptions(
    'help|h'        => sub { printHelpAndExit(); },
    %opts
 );

# No ARGV should be leaved there
if(scalar(@ARGV))
{
    Logger::warn("Options not recognised : ".join(" ", @ARGV));
    printHelpAndExit();
}

foreach my $ref (keys %PARAMS)
{

    if($PARAMS{$ref}->{'mandatory'} and not ${$PARAMS{$ref}->{'target'}})
    {
        Logger::info('Arg:'.$ref.' must be given !');
        printHelpAndExit();
    }
}


main();
