package NAP::Messaging::Catalyst::Controller::Root;
use NAP::policy 'class';
require NAP::Messaging::Catalyst::Handle404;
BEGIN { extends 'Catalyst::Controller::JMS' }

# ABSTRACT: default root controller, handles messages received in error

=head1 DESCRIPTION

This controller defines a C<default> action that will send messages
received in error (i.e. for destinations that we did not subscribe to,
something that the STOMP protocol usually does not allow to happen) to
a DLQ.

=cut

__PACKAGE__->config(
    namespace => '/',
);

with 'NAP::Messaging::Catalyst::Handle404::RootRole';
