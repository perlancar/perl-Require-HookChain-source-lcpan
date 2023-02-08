## no critic: TestingAndDebugging::RequireUseStrict
package Require::HookChain::source::lcpan;

#IFUNBUILT
use strict;
use warnings;
#END IFUNBUILT
use Log::ger;

# preload modules we need to avoid infinite loop
use App::lcpan::Call qw(call_lcpan_script);
use File::chdir;
use File::Spec;
use IPC::System::Options;
use JSON::MaybeXS;
use Perinci::CmdLine::Call; # lazy-loaded by App::lcpan::Call

# AUTHORITY
# DATE
# DIST
# VERSION

sub new {
    my ($class, $die, $tempdir) = @_;
    $die = 1 unless defined $die;
    if (defined $tempdir) {
        unless (-d $tempdir) { die "[RHC::source::lcpan] Fatal: Supplied tempdir '$tempdir' is not a directory" }
    } else {
        $tempdir = File::Spec->tmpdir;
        unless (-d $tempdir) { die "[RHC::source::lcpan] Fatal: Can't find tempdir '$tempdir'" }

        $tempdir = "$tempdir/lcpan";
        unless (-d $tempdir) {
            mkdir $tempdir, 0755 or die "[RHC::source::lcpan] Fatal: Can't mkdir '$tempdir': $!";
        }
    }
    bless { die => $die, tempdir=>$tempdir }, $class;
}

sub Require::HookChain::source::lcpan::INC {
    my ($self, $r) = @_;

    # safety, in case we are not called by Require::HookChain
    return () unless ref $r;

    my $filename = $r->filename;

    if (defined $r->src) {
        log_trace "[RHC:source::lcpan] source code already defined for $filename, declining";
        return;
    }

    # get dist name
    (my $mod = $filename) =~ s/\.pm\z//; $mod =~ s!/!::!g;
    my $res = call_lcpan_script(argv => ['mod', $mod]);
    unless ($res->[0] == 200) {
        if ($self->{die}) { die "[RHC::source::lcpan] Cannot 'lcpan mod $mod': $res->[0] - $res->[1]" } else { return undef } ## no critic: TestingAndDebugging::ProhibitExplicitReturnUndef
    }
    unless ($res->[2] && $res->[2][0]{dist}) {
        if ($self->{die}) { die "[RHC::source::lcpan] Cannot find distribution for module '$mod'" } else { return undef } ## no critic: TestingAndDebugging::ProhibitExplicitReturnUndef
    }

    # mkdir dist subdir
    my $dist = $res->[2][0]{dist};
    unless (-d "$self->{tempdir}/$dist") {
        mkdir "$self->{tempdir}/$dist", 0755 or do {
            if ($self->{die}) { die "[RHC::source::lcpan] Cannot mkdir '$self->{tempdir}/$dist': $!" } else { return undef } ## no critic: TestingAndDebugging::ProhibitExplicitReturnUndef
        };
    }
    local $CWD = "$self->{tempdir}/$dist";
    my @files = glob "*";
    unless (@files) {
        # extract dist from local cpan
        $res = call_lcpan_script(argv => ["extract-dist", $dist]);
        unless ($res->[0] == 200) {
            if ($self->{die}) { die "[RHC::source::lcpan] Cannot 'lcpan extract-dist $dist': $res->[0] - $res->[1]" } else { return undef } ## no critic: TestingAndDebugging::ProhibitExplicitReturnUndef
        }
    }

    # try to find module source code
    (my $basename = $filename) =~ s!.+/!!;
    my @search = (
        "$files[0]/lib/$filename",
        "$files[0]/$filename",
        $filename,
        "$files[0]/$basename",
        $basename,
    );
    for my $f (@search) {
        if (-f $f) {
            open my $fh, "<", $f or do {
                if ($self->{die}) { die "[RHC::source::lcpan] Cannot read $self->{tempdir}/$dist/$f: $!" } else { return undef } ## no critic: TestingAndDebugging::ProhibitExplicitReturnUndef
            };
            my $src = join "", <$fh>;
            close $fh;
            $r->src($src);
            return 1;
        }
    }
    if ($self->{die}) { die "[RHC::source::lcpan] Cannot find $filename in $self->{tempdir}/$dist" } else { return undef } ## no critic: TestingAndDebugging::ProhibitExplicitReturnUndef
}

1;
# ABSTRACT: Load module from local CPAN mirror

=for Pod::Coverage .+

=head1 SYNOPSIS

In Perl code:

 use Require::HookChain 'source::lcpan'; # optional extra arguments: $die, $tempdir
 use Ask; # will retrieve from local CPAN, even if it's installed

On the command-line:

 # will retrieve from MetaCPAN if Ask is not installed
 % perl -MRHC=-end,1,source::lcpan -MAsk -E...


=head1 DESCRIPTION

To use this, you must have a working local CPAN mirror managed by L<App::lcpan>.
Install that module first and follow its installation instruction.

Optional extra import arguments:

=over

=item * $die

Bool, default true. If set to true, will die when failing to find and read
module source from local CPAN mirror. Otherwise, will just decline to let
Require::HookChain to other hooks.

=item * $tempdir

Str. Location to extract CPAN distribution into. Defaults to C<$TMPDIR/lcpan>
where C<$TMPDIR> is retrieved from C<< File::Spec->tmpdir >>. Under this
directory is the subdirectory of name of distribution. And under that
subdirectory is the extracted archive from each CPAN distribution retrieved from
local CPAN mirror.

=back

Some other caveats:

=over

=item * This module is most probably not suitable for use in production

=back


=head1 SEE ALSO

L<App::lcpan>

L<Require::HookChain>

L<Require::HookChain::source::metacpan>
