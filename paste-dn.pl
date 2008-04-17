#!/usr/bin/perl -w
#
# paste-dn.pl - http://paste.debian.net/ XML-RPC client
#
# Author: Hanno Hecker <vetinari@ankh-morp.org>
# Licence: AGPL 3.0 (http://www.fsf.org/licensing/licenses/agpl-3.0.html)
# Version: $Id$
# SVN: http://svn.ankh-morp.org:8080/tools/paste-dn/
#
# ToDo: 
#  * add help texts
#  * "edit" action (i.e. "get", call system($EDITOR, $tempfile), "add")?
#  * wishlist :)
#  * "get" formatting?
#  * delete expired or deleted entries from history file
#  * iconv $code from $encoding to UTF-8 before adding?
# 
use strict;
use Getopt::Long;
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

$0 =~ s#.*/##;
my $VERSION = '0.2 ($Rev$)';
my $settings = $ENV{HOME}."/.paste-dn.rc";

## Don't change, edit $settings file:
## KeYInAnyCaSE: value
## AnoThErKey: other-value
my $history  = $ENV{HOME}."/.paste-dn.history";
my %config = (
    server   => "http://paste.debian.net/server.pl",
    user     => "anonymous",
    lang     => "",
    expires  => 86400 * 3, # 
    history_file => $history,
);
my $action = "help";
my %help   = (
        'add'  => "\n"
             ."Usage: $0 add [OPTIONS] [CODE]\n"
             ."  Adds a new paste to http://paste.debian.net/\n"
             ."  If no code is given on the command line, it will read from\n"
             ."  stdin.\n"
             ."  Your paste infos are saved to $history\n",
        'get'  => "\n"
             ."Usage: $0 get [OPTIONS] ID\n"
             ."  Fetches the paste with id ID from paste.debian.net\n"
             ."  To 'download' a paste use something like\n"
             ."   $0 get ID | tail -n +5 > OUTFILE\n",
        'del'  => "FIXME: help for 'del'",
        'lang' => "FIXME: help for 'lang'",
        # 'help' => "FIXME: help",
    );

if (@ARGV and $ARGV[0] !~ /^-/) {
    $action = shift @ARGV;
}

&read_settings();

GetOptions(
        "user=s"    => \$config{user},
        "server=s"  => \$config{server},
        "expires=s" => \$config{expires},
        "lang=s"    => \$config{lang},
        "help"      => sub { print &usage(); exit 0; },
        "version"   => sub { print "paste-dn v$VERSION\n"; exit 0; },
    )
  or die &usage();

if ($action and $action eq "help") {
    $action = shift @ARGV
      if (@ARGV and $ARGV[0] !~ /^-/);
    &help($action);
    exit 0;
}

my $paste = PasteDN->new(%config);
if ($paste->can($action)) {
    $paste->$action();
}
else {
    die "$0: err... unknown action $action...\n";
}

sub read_settings {
    open SET, $settings
      or return;
    while (defined (my $line = <SET>)) {
        next unless $line =~ /^(\w+):\s+(.*)$/;
        my ($key, $value) = (lc $1, $2);
        unless (exists $config{$key}) {
            warn "$0: unknown config key '$key' found\n";
            next;
        }
        ($config{$key} = $value) =~ s/^\s*(.*?)\s*$/$1/;
    }
    close SET;
}

sub usage {
    return <<_END;
$0: Usage: $0 ACTION [OPTIONS] [CODE]
  valid actions are: add, del, get, lang
  for more specific info on these actions use 
    $0 help ACTION
  Available OPTIONS:
    --help          - this help 
    --user=USERNAME - paste as USERNAME instead of "anonymous"
    --server=URL    - use URL instead of $config{server}
    --lang=LANG     - use LANG for syntax highlight 
                      ('$0 lang' for available languages)
    --expires=SEC   - expires in SEC seconds (def: $config{expires})
    --version       - print version and exit
_END
}

sub help {
    print usage();
    print $help{$_[0]},"\n" if (exists $help{$_[0]});
    exit 0;
}

package PasteDN;
use Frontier::Client;
use Date::Parse;
use POSIX qw(strftime);

sub new {
    my $me   = shift;
    my %args = @_;
    my $type = ref($me) || $me;
    my $self = {};
    bless $self, $type;
    foreach (keys %args) {
        $self->{$_} = $args{$_};
    }
    $self->{expires}  += time;
    $self->{_service} = Frontier::Client->new(url => $self->{server});
    $self;
}

sub lang {
    my $self  = shift;
    my $paste = $self->{_service};
    my $rc    = $paste->call("paste.getLanguages");
    die $rc->{statusmessage},"\n" if $rc->{rc};
    ## print $rc->{statusmessage},"\n";
    print "Available syntax highlights:\n";
    foreach (@{$rc->{langs}}) {
        print " $_\n";
    }
}

sub get {
    my $self = shift;
    my $id   = shift @ARGV;
    die "$0: no id given\n" unless $id;
    my $paste = $self->{_service};
    my $rc    = $paste->call("paste.getPaste", $id);
    die $rc->{statusmessage},"\n" if $rc->{rc};
    # ugly, but dates are ok then...
    # FIXME: probably only works with paste.d.n's timezone:
    my $stime    = str2time($rc->{submitdate}, "CET") - 3600;
    my $sub_date = strftime('%Y-%m-%d %H:%M:%S', localtime $stime);
    my $exp_date = strftime('%Y-%m-%d %H:%M:%S', 
                    localtime($stime + $rc->{expiredate}));
    print "User: ", $rc->{submitter}, "\n",
          "Date: $sub_date\n",
          "Expires: $exp_date\n",
          "---------------------------------\n",
          $rc->{code},"\n";
}

sub del {
    my $self = shift;
    my %entry = ();
    my $id   = shift @ARGV;
    die "$0: no id given\n" unless $id;
    open FILE, $self->{history_file}
      or die "$0: failed to open history file: $!\n";
    { 
        local $/ = "\n\n"; 
        while (<FILE>) {
            s#^[\n\s]+##ms;
            s#[\n\s]+$##ms;
            next unless $_;
            %entry = map { /^(\S+):\s*(.*?)\s*$/;
                           ($1, $2 ? $2 : "")     } split /\n/, $_;
            last if ($entry{Entry} and $entry{Entry} eq $id);
            %entry = ();
        }
    }
    die "$0: Entry for $id not found...\n" unless $entry{Entry};
    die "$0: No Digest for $id\n" unless $entry{Digest};
    die "$0: Entry $id expired at ", scalar(localtime($entry{Expires})),"\n"
      if ($entry{Expires} and $entry{Expires} < time);

    my $paste = $self->{_service};
    my $rc = $paste->call("paste.deletePaste", $entry{Digest});
    die $rc->{statusmessage},"\n" if $rc->{rc};
    print $rc->{statusmessage},"\n",
          "$0: deleted paste id ",$rc->{id},"\n";
}

sub add {
    my $self = shift;

    my $code = undef;
    if (@ARGV) {
        $code = join("\n", @ARGV);
    }
    else {
        { local $/ = undef; $code = <STDIN>; }
    }
    die "$0: no code given\n"
      unless $code;

    my $paste = $self->{_service};
    my $rc = $paste->call("paste.addPaste", $code, 
                            $self->{user}, 
                            $self->{expires} - time, 
                            $self->{lang});
    die $rc->{statusmessage},"\n" 
      if $rc->{rc};
    print $rc->{statusmessage},"\n";
    print "To delete this entry, use: $0 del $rc->{id}\n";
    $self->save_entry($rc);
}

sub save_entry {
    my ($self, $rc) = @_;
    # return unless $self->{save_pastes};
    my $file = $self->{history_file}
     or return;
    open FILE, ">>", $file or die "$0: failed to open $file: $!\n";
    seek FILE, 0, 2        or die "$0: Failed to seek: $!\n";
    print FILE "Server: ",  $self->{server}, "\n",
               "Entry: ",   $rc->{id},       "\n",
               "Lang: ",    $self->{lang},   "\n",
               "Expires: ", $self->{expires},"\n",
               "Digest: ",  $rc->{digest},   "\n\n"
      or die "$0: Failed to save paste: $!\n";
    close FILE             or die "$0: Failed to save paste: $!\n";
}

# vim: ts=4 sw=4 expandtab syn=perl
