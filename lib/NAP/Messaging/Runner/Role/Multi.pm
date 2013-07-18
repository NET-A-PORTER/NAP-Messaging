package NAP::Messaging::Runner::Role::Multi;
use NAP::policy 'role','tt';
use POSIX ':sys_wait_h';
use Hash::Util::FieldHash qw(fieldhash);

# ABSTRACT: role providing the common parts of multi runners

=head1 DESCRIPTION

This role is used by L<NAP::Messaging::MultiRunner> and
L<NAP::Messaging::MultiRunner::Partitioned>. It provides the common
behaviour.

=cut

# yes, this is a per-process global, we want to stop all consuming
# instances at process end, to make sure all children are stopped

fieldhash my %instances;

=method C<BUILD>

"After" modifier. Keep track of this instance, to stop all its
children at C<END> time.

=method C<DEMOLISH>

"Before" modifier: stop all my children.

"After" modifier: stop tracking this instance.

=cut

sub BUILD {}
after BUILD => sub { $instances{$_[0]} = $_[0] };
sub DEMOLISH {}
before DEMOLISH => sub { $_[0]->stop_children };

END {
    $_->stop_children for values %instances;
}
our @trapped_signals = qw(INT TERM QUIT);
for my $signal (@trapped_signals) {
    ## no critic RequireLocalizedPunctuationVars
    $SIG{$signal} = sub { $_->stop_children for values %instances };
}

=attr C<stopping>

Boolean. True if we just received a signal, and are now killing
children.

=cut

has stopping => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

=head1 REQUIRED METHODS

=head2 C<remove_child>

  $self->remove_child($pid);

Usually delegated to a L<NAP::Messaging::Runner::ChildSupervisor>

=head2 C<fork_all>

  $self->fork_all();

Usually delegated to a L<NAP::Messaging::Runner::ChildSupervisor>

=head2 C<stop_children>

  $self->stop_children($signal);

Usually delegated to a L<NAP::Messaging::Runner::ChildSupervisor>

=head2 C<appclass>

Used to get the logger.

=head2 C<run>

Usually obtained via inheritance from L<NAP::Messaging::Runner>

=cut

requires qw(remove_child fork_all stop_children appclass run);

=method C<run_multiple>

Enters an infinite loop:

=for :list
* fork up to the needed number of children, via L</fork_all>
* wait for a child to die, or a signal to be received
* if a child died, log the event and update the internal status via L</remove_child>

=cut

sub run_multiple {
    my ($self) = @_;

    while (not $self->stopping) {
        $self->fork_all;

        my $dead_child = waitpid(-1,0);
        next if $dead_child < 1; # interrupted by a signal

        my $exit_code = ${^CHILD_ERROR_NATIVE};
        my $exit_message = 'unclear death';
        if (WIFEXITED($exit_code)) {
            my $status = WEXITSTATUS($exit_code);
            $exit_message = "normal exit, status $status";
        }
        elsif (WIFSIGNALED($exit_code)) {
            my $signal = WTERMSIG($exit_code);
            $exit_message = "killed by signal $signal";
        }
        $self->appclass->log->warn("Process $dead_child died ($exit_message), starting a new one");

        $self->remove_child($dead_child);
    }
}

=method C<run_consumer_child>

Delegate to L</run>.

=cut

sub run_consumer_child { shift->run }
