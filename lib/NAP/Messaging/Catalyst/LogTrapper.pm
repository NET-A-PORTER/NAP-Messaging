package NAP::Messaging::Catalyst::LogTrapper {
use NAP::policy 'role';

# ABSTRACT: Catalyst plugin to tie STDIN/STDERR to the logger

after setup_finalize => sub {
    my ($c) = @_;

    my $config = $c->config->{logtrapper} // {};

    return unless $config->{enable};

    tie *STDOUT,'NAP::Messaging::Catalyst::LogTrapper::Tied',\*STDOUT;
    tie *STDERR,'NAP::Messaging::Catalyst::LogTrapper::Tied',\*STDERR;
};
};

package NAP::Messaging::Catalyst::LogTrapper::Tied {
use NAP::policy 'class';
use Log::Log4perl ();

has original_fh => (
    is => 'ro',
    required => 1,
);

sub TIEHANDLE {
    my ($class,$fh) = @_;

    open my $original,'>&',$fh;
    return $class->new({original_fh=>$original});
}

sub PRINT {
    my $self = shift;

    # a loop! let's print to the real filehandle
    if ((caller)[0]=~/^Log::/) {
        print {$self->original_fh} "@_";
        return;
    }

    local $@ = $@;
    local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + 1;

    Log::Log4perl->get_logger()->info("[LogTrapper] @_");
}

# something, sometimes, wants to reopen STDOUT/STDERR
# let's pretend we can do that
sub OPEN { return shift }
}
