package NAP::Messaging::Role::WithTiming;
use NAP::policy 'role','tt';
use NAP::Messaging::Timing;

# ABSTRACT: access the timing facility

=head1 Methods provided

=head2 C<timing>

  $self->timing(%details);

Returns a L<NAP::Messaging::Timing> object tied to the correct logger,
and with C<details> set to the hash provided (the C<caller> key is set
to the class name).

=cut

requires '_c';

sub timing {
    my ($self,@details) = @_;

    return NAP::Messaging::Timing->new({
        logger => $self->_c->timing_log,
        details => [caller=>ref($self),@details],
    });
}
