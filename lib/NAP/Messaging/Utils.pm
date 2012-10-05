package NAP::Messaging::Utils;
use NAP::policy 'exporter';
use Sub::Exporter -setup => {
    exports => [ 'object_message' ],
};
use Class::ConfigHash;

# ABSTRACT: various utility functions

=func C<object_message>

  sub routes {
    return {
      input_queue => {
        msgtype => {
          spec => {
            type => '//rec',
            required => { value => '//str'},
          },
          code => object_message(\&handle),
        },
      },
    };
  }

  sub handle {
    my ($self,$message,$headers) = @_;
    say $headers->destination;
    say $message->value;
  }

This function takes a message-handling coderef, and wraps it making
sure that the C<$message> and C<$headers> parameters are passed as
L<Class::ConfigHash> objects instead of naked hashrefs.

=cut

sub object_message {
    my ($coderef) = @_;

    return sub {
        my ($self,$message,$headers) = @_;
        return $self->$coderef(
            Class::ConfigHash->_new($message),
            Class::ConfigHash->_new($headers),
        )
    }
}
