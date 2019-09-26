#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long qw(:config no_auto_abbrev);

my $login = getlogin();
my $libPath = "/home/$login";
require lib;
lib->import( $libPath );
require common::log;
require common::Logger;
require common::Result;
use File::Basename;
my $currentScriptName = basename($0);

my $whatMagicIsDoneHere = 'some usefull information about what this tool is doing'; ## printed by --help

# create your parameters variables 
my ($arg1, $arg2, $arg3);

##### define what your script and where it should be stored
# 'argumentName' => ## what you want in input of your script 
#        string =>1,             ## set to 1 if you need an input value. 0 if you set a flag
#        mandatory => 1,         ## set to 1 if this value is mandatory
#        help   => 'crazy arg1', ## what --help should prompt about this argument
#        target => \$arg1,       ## on which variable i should store the result if i got one
# 
our  %PARAMS    = (
    'arg1'  => {
        mandatory   => 1,
        string      => 1,
        help        => 'crazy arg1',
        target      => \$arg1,
    },
    'arg2' => {
        mandatory   => 1,
        string      => 1,
        help        => 'crazy arg2',
        target      => \$arg2,
    },
    'arg3' => {
        mandatory   => 1,
        string      => 1,
        help        => 'crazy arg3',
        target      => \$arg3,
    },
);


################################
#   YOU CODE SHOULD BE HERE
################################

sub doIt
{
    my ($commonScriptObject, %params) = @_;

    Logger::log("YOUR CODE HERE");
    Logger::log('arg1',$arg1,'arg2',$arg2,'arg3',$arg3);
    my $fnret = promptValidation();
    not $fnret and return $fnret;
    Logger::log("YOUR CODE HERE");

    return Result->ok();
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
