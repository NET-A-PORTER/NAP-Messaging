package NAP::Messaging::Base::Consumer;
use NAP::policy 'class';
use Moose::Meta::Class;

# ABSTRACT: base class for NAP JMS consumers

=head1 SYNOPSIS

  package MyApp::Consumer::One;
  use NAP::policy 'class';
  extends 'NAP::Messaging::Base::Consumer';

  sub routes {
    return {
      my_input_queue => {
        my_message_type => {
          spec => { type => '//any' },
          code => \&my_consume_method,
        },
      },
    }
  }

  sub my_consume_method {
    my ($self,$message,$headers) = @_;

    # do something
  }

=head1 DESCRIPTION

This base class simplifies writing consumers. Most of the
functionality comes from these roles:

=for :list
* L<NAP::Messaging::Role::Component> to get loaded by Catalyst
* L<NAP::Messaging::Role::ConsumesJMS> to get all the consumer functionality
* L<NAP::Messaging::Role::WithLogger> to get a C<log> method
* L<NAP::Messaging::Role::WithAMQ> to get an C<amq> method
* L<NAP::Messaging::Role::WithResponse> to get a C<response> attribute

L<NAP::Messaging::Role::ConsumesJMS> is the important one.

Your "consume method" / coderef will be called as a method on an
instance of your subclass, with the de-serialised message as first
argument, and the hashref of headers as second argument:

  $self->$coderef($message,\%headers);

=cut

with 'NAP::Messaging::Role::Component';
with 'NAP::Messaging::Role::ConsumesJMS',
     'NAP::Messaging::Role::WithLogger',
     'NAP::Messaging::Role::WithAMQ',
     'NAP::Messaging::Role::WithResponse';

sub _kind_name { 'Consumer' }

sub _wrap_coderef {
    my ($self_consume,$c_out,$consume) = @_;

    return sub {
        my ($self_controller,$c,$message,$headers) = @_;

        $self_consume->$consume($message,$headers);
        my $response = $self_consume->response;

        $c->stash->{message} = $response;
        $c->response->status(200);

        return;
    };
}
