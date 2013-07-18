package NAP::Messaging::Role::WithLogger;
use NAP::policy 'role','tt';

# ABSTRACT: access the logger

=head1 Methods provided

=head2 C<log>

Shortcut for C<< $the_application->log >>.

=cut

requires '_c';

sub log { ## no critic ProhibitBuiltinHomonyms
    return shift->_c->log
}
