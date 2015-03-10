package NAP::Messaging::Runner::ChildSupervisor;
use NAP::policy 'class','tt';
use Moose::Util::TypeConstraints;
use POSIX ':sys_wait_h';

# ABSTRACT: class to supervise child processes

=head1 SYNOPSIS

  my $children = NAP::Messaging::Runner::ChildSupervisor->new({
    trapped_signals => [ qw(INT TERM QUIT) ],
    code => sub { ... },
  })

=head1 DESCRIPTION

This class gives you a set of methods to fork child processes, keep
track of them, and handle a few signals. The user of objects of this
class is still responsible to set up a run-loop and call C<waitpid>.

=attr C<name>

String attribute, used in error messages and process name.

=cut

has name => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

=attr C<trapped_signals>

Arrayref of keys for the C<%SIG> hash; these are the signals that the
user traps, and that should be reset to their default handler after
the C<fork>.

=cut

has trapped_signals => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
    default => sub { [ ] },
);

=attr C<stopping>

Boolean, true if the whole set of processes is shutting down. It will
prevent more children from being forked.

=cut

has stopping => (
    is => 'ro',
    writer => '_set_stopping',
    isa => 'Bool',
    default => 0,
);

=attr C<logger>

A logger (must do C<info>, C<warn> and C<error>). Required.

=cut

has logger => (
    is => 'ro',
    isa => duck_type([qw(info warn error)]),
    required => 1,
);

=attr C<instances>

How many children this supervisor should keep alive. Defaults to 1.

=cut

has instances => (
    is => 'ro',
    isa => 'Int',
    default => 1,
);

=attr C<code>

Coderef called in each child process, it should execute some sort of
infinite run-loop.

=cut

has code => (
    is => 'ro',
    isa => 'CodeRef',
    required => 1,
);

=method C<remove_child>

  $self->remove_child($pid);

Call this when C<waitpid> tells you that a child process has
died. Pass the process id of the dead child.

=method C<children_count>

Returns the number of children currently believed to exist. Should
never be more than L</instances>.

=method C<children>

Returns all the process ids of the children currently believed to
exist, as a list.

=cut

has _children => (
    is => 'ro',
    isa => 'ArrayRef[Int]',
    default => sub { [ ] },
    traits => ['Array'],
    handles => {
        _add_child => 'push',
        remove_child => 'delete',
        _find_child => 'first_index',
        children_count => 'count',
        children => 'elements',
    },
);

# remove by PID instead of position
around remove_child => sub {
    my ($orig,$self,$child) = @_;
    my $idx = $self->_find_child(sub{$_ == $child});
    return if $idx < 0;
    return $self->$orig($idx);
};

=method C<fork_all>

If not L</stopping>, and L</instances> is greater than 0, call
L</fork_and_run> enough times to bring L</children_count> up to
L</instances>.

=cut

sub fork_all {
    my ($self) = @_;

    return if $self->stopping;

    my $instances = $self->instances;

    return if $instances <= 0;

    $self->logger->info(
        sprintf 'Starting up to %d %s children',
        $instances,$self->name
    );

    while ($self->children_count < $instances) {
        $self->_add_child($self->fork_and_run);
    }
}

=method C<fork_and_run>

If we're L</stopping>, do nothing. Otherwise, fork. Return the
PID to the parent process, call C<< $self->code >> in the child
process.

=cut

sub fork_and_run {
    my ($self) = @_;

    return if $self->stopping;

    my $pid = fork();
    if (not defined $pid) {
        $self->logger->error("Can't fork: $!");
        exit 1;
    }
    return $pid if $pid;
    my $name = ' ('.$self->name.')';
    $0 =~ s/(?: \(.*\))?\z/$name/;

    for my $signal (@{$self->trapped_signals}) {
        ## no critic (RequireLocalizedPunctuationVars)
        $SIG{$signal} = 'DEFAULT';
    }

    $self->logger->info("Child$name running as $$");

    $self->code->();
}

=method C<stop_children>

  $self->stop_children($signal);

Set L</stopping> to 1, then kill
each child process with the given C<$signal>.

=cut

sub stop_children {
    my ($self,$signal) = @_;
    $signal //= 'TERM';

    $self->_set_stopping(1);

    return if $self->children_count <= 0;

    $self->logger->info(sprintf 'stopping all %s children',
                    $self->name)
        if Log::Log4perl->initialized; # this may happen at END time

    for my $pid ($self->children) {
        kill $signal,$pid;
        waitpid $pid,0;
        $self->remove_child($pid);
        $self->logger->info("stopped $pid")
            if Log::Log4perl->initialized; # this may happen at END time
    }

    return;
}
