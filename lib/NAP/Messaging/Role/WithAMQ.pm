package NAP::Messaging::Role::WithAMQ;
use NAP::policy 'role';

# ABSTRACT: access the ActiveMQ model

=head1 Methods provided

=head2 C<amq>

Shortcut for C<< $the_application->model('MessageQueue') >>.

=cut

requires '_c';

sub amq {
    return shift->_c->model('MessageQueue');
}
