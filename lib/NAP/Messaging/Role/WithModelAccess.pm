package NAP::Messaging::Role::WithModelAccess;
use NAP::policy 'role';

# ABSTRACT: access any Catalyst model

=head1 Methods provided

=head2 C<model>

Shortcut for C<< $the_application->model(@_) >>.

=cut

requires '_c';

sub model {
    my $self = shift;
    return $self->_c->model(@_);
}
