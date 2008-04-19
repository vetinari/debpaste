#!/usr/bin/perl -w
#
# paste-dn - http://paste.debian.net/ XML-RPC client
#
# Author: Hanno Hecker <vetinari@ankh-morp.org>
# Licence: AGPL 3.0 (http://www.fsf.org/licensing/licenses/agpl-3.0.html)
# Version: $Id$
# SVN: http://svn.ankh-morp.org:8080/tools/paste-dn/
# 
# Required: 
#  deb: perl-base perl-modules 
#       libtimedate-perl libfrontier-rpc-perl libtext-iconv-perl
#
# ToDo: 
#  * "get" formatting?
#  * wishlist :)
# 
use strict;
use Getopt::Long;
my %config;

sub usage {
    return <<_END;
$0: Usage: $0 ACTION [OPTIONS] [CODE]
  valid actions are: add, del, get, lang, expire
  for more specific info on these actions use 
    $0 help ACTION
  Available OPTIONS:
    --help          - this help 
    --user=USERNAME - paste as USERNAME instead of "anonymous"
    --server=URL    - use URL instead of $config{server}
    --lang=LANG     - use LANG for syntax highlight 
                      ('$0 lang' for available languages)
    --expires=SEC   - expires in SEC seconds (def: $config{expires})
    --encoding=ENC  - when adding new paste, use ENC as encoding of file, 
                      default: UTF-8
    --noheader      - when "get"ting entries, don't print header, just dump
                      the paste to stdout.
    --version       - print version and exit
_END
}

binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

$0 =~ s#.*/##;
my $VERSION = '0.4 ($Rev$)';
my $settings = $ENV{HOME}."/.paste-dn.rc";

## Don't change, edit $settings file:
## KeYInAnyCaSE: value
## AnoThErKey: other-value
my $history  = $ENV{HOME}."/.paste-dn.history";
%config = (
    server   => "http://paste.debian.net/server.pl",
    user     => "anonymous",
    lang     => "",
    expires  => 86400 * 3, # 
    history_file => $history,
    no_get_header => 0,
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
             ."   $0 get --noheader ID > OUTFILE\n",
        'del'  => "\n"
             ."Usage: $0 del [OPTIONS] ID\n"
             ."  Deletes paste with id ID. This must be an ID which you have\n"
             ."  pasted before (and is in your history file)\n",
        'lang' => "\n"
             ."Usage: $0 lang [OPTIONS]\n"
             ."  Dumps the list of available languages for syntax highlighting\n", 
        'edit' => "\n"
             ."Usage: $0 edit [OPTIONS] ID\n"
             ."  Downloads the paste with id ID, spawns an editor (\$EDITOR)\n"
             ."  and sends the edited file as new paste\n",
        'expire' => "\n"
             ."Usage: $0 expire [OPTIONS] [ID]\n"
             ."  Removes the entry ID from history file. If no ID is given,\n"
             ."  it removes all entries which are expired.\n",
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
        "encoding=s"=> \$config{encoding},
        "noheader"  => \$config{no_get_header},
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
if ($paste->can($action) and $action ne "new") {
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

sub help {
    print usage();
    print $help{$_[0]},"\n" if (exists $help{$_[0]});
    exit 0;
}

###################################################################

package PasteDN;
use Frontier::Client;
use Date::Parse;
use POSIX qw(strftime);
use File::Temp qw(tempfile);
use Text::Iconv;

sub new {
    my $me   = shift;
    my %args = @_;
    my $type = ref($me) || $me;
    my $self = {};
    bless $self, $type;
    foreach (keys %args) {
        $self->{$_} = $args{$_};
    }
    unless (exists $self->{editor}) {
        $self->{editor} = $ENV{EDITOR} ? 
                            $ENV{EDITOR} : ($ENV{VISUAL} ? 
                                            $ENV{VISUAL} : "/usr/bin/editor");
    }
    $self->{encoding} = "UTF-8" unless $self->{encoding};
    $self->{expires}  += time;
    $self->{_service} = Frontier::Client->new(url => $self->{server});
    $self;
}

sub _to_utf8 {
    my ($self,$txt) = @_;
    my $enc = $self->{encoding};
    return $txt if $enc eq "UTF-8";

    my $i = eval { Text::Iconv->new($enc, "UTF-8"); };
    die "$0: unsupported encoding $enc\n" if $@;

    my $new = $i->convert($txt);
    return $txt unless $new;
    return $new;
}

sub _error {
    my ($self, $msg) = @_;
    unlink $self->{_tempfile} if $self->{_tempfile};
    die "$0: $msg\n";
}

sub lang {
    my $self  = shift;
    my $rc    = $self->{_service}->call("paste.getLanguages");
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
    my $rc    = $self->{_service}->call("paste.getPaste", $id);
    die $rc->{statusmessage},"\n" if $rc->{rc};
    # ugly, but dates are ok then...
    # FIXME: probably only works with paste.d.n's timezone:
    my $stime    = str2time($rc->{submitdate}, "CET") - 3600;
    my $sub_date = strftime('%Y-%m-%d %H:%M:%S', localtime $stime);
    my $exp_date = strftime('%Y-%m-%d %H:%M:%S', 
                    localtime($stime + $rc->{expiredate}));
    unless ($self->{no_get_header}) {
        print "User: ", $rc->{submitter}, "\n",
              "Date: $sub_date\n",
              "Expires: $exp_date\n",
              "---------------------------------\n";
    }
    print $rc->{code};
}

sub edit {
    my $self = shift;
    my $id   = shift @ARGV;
    die "$0: no id given\n" unless $id;

    my $rc    = $self->{_service}->call("paste.getPaste", $id);
    die $rc->{statusmessage},"\n" if $rc->{rc};
    my $new = $self->_spawn_editor($rc->{code});
    if (!$new or ($new eq $rc->{code})) {
        print "$0: not changed, aborting...\n";
        exit 0;
    }
    ## FIXME: text from paste.debian.net is probably UTF-8
    ## $new = $self->_to_utf8($new);
    $rc = $self->{_service}->call("paste.addPaste", $new,
                            $self->{user},
                            $self->{expires} - time,
                            $self->{lang});
    die $rc->{statusmessage},"\n"
      if $rc->{rc};
    print $rc->{statusmessage},"\n";
    print "To delete this entry, use: $0 del $rc->{id}\n";
    $self->save_entry($rc);
}

sub _spawn_editor {
    my ($self, $txt) = @_;
    my $fh;

    ($fh, $self->{_tempfile}) = tempfile("paste-dn.XXXXXX", DIR => "/tmp");

    $self->_error("Could not create temp file: $!")
      unless ($fh and $self->{_tempfile});
    print $fh $txt or $self->_error("Could not print to tempfile: $!");
    close $fh      or $self->_error("Failed to close tempfile: $!");

    if (system($self->{editor}, $self->{_tempfile}) != 0) {
        $self->_error("failed to execute: $!") 
            if $? == -1;

        $self->_error(sprintf('child died with signal %d, %s coredump',
                            ($? & 127),  ($? & 128) ? 'with' : 'without'))
            if $? & 127;

        $self->error(sprintf('editor exited with value %d', $? >> 8));
    }

    open FH, $self->{_tempfile}
      or $self->_error("Failed to open temp file: $!");
    { 
        local $/ = undef; 
        $txt = <FH>; 
    };
    close FH;
    unlink $self->{_tempfile};
    return $txt;
}

sub delete { $_[0]->del(); }
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

    my $rc = $self->{_service}->call("paste.deletePaste", $entry{Digest});
    die $rc->{statusmessage},"\n" if $rc->{rc};
    print $rc->{statusmessage},"\n",
          "$0: deleted paste id ",$rc->{id},"\n";
    $self->_expire($rc->{id});
}

sub expire {
    my $self = shift;
    my $id   = shift @ARGV;
    $self->_expire($id);
}

sub _expire {
    my ($self, $id) = @_;
    my @history = ();
    my %entry;
    my @ids = ();
    open FILE, $self->{history_file}
      or return;
    { 
        local $/ = "\n\n";
        while (<FILE>) {
            s#^[\n\s]+##ms;
            s#[\n\s]+$##ms;
            next unless $_;
            %entry = map { /^(\S+):\s*(.*?)\s*$/;
                           ($1, $2 ? $2 : "")     } split /\n/, $_;

            ## print "ID: $entry{Entry}\n";
            if ($id) {
                if ($entry{Entry} and $entry{Entry} eq $id) {
                    push @ids, $entry{Entry};
                    next;
                }
            }
            elsif ($entry{Expires} and $entry{Expires} < time) {
                push @ids, $entry{Entry};
                next;
            }
            push @history, { %entry };
        }
    }
    close FILE;
    open FILE, ">", $self->{history_file} 
      or die "$0: Failed to open history file: $!\n";
    foreach my $h (@history) {
        foreach (keys %{$h}) {
            next unless $_;
            print FILE "$_: $h->{$_}\n";
        }
        print FILE "\n";
    }
    close FILE  or die "$0: failed to write: $!\n";
    print "$0: expired ", scalar(@ids), " entries from history", 
            (@ids ? ": ".join(", ", @ids) : ""), "\n";
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

    $code = $self->_to_utf8($code);
    my $rc = $self->{_service}->call("paste.addPaste", $code, 
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
