package NAP::Messaging::Utils;
use NAP::policy 'exporter';
use Sub::Exporter -setup => {
    exports => [ 'object_message',
                 'ignore_extra_fields',
                 'ignore_extra_fields_deep',
             ],
};
use Class::ConfigHash;
use Data::Visitor::Callback;

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

=func C<ignore_extra_fields>

  my $rx_spec_lax = ignore_extra_fields($rx_spec_strict);

If the C<$rx_spec_strict> is a L<Data::Rx> schema specification for a
record (i.e. it's a hashref with a C<type> key with value C<//rec> or
similar), add a C<< rest => '//any' >> to it, making it ignore
unexpected fields.

Doing this in your B<consumer> validators allows the producers to add
information without breaking the consumers.

=cut

sub ignore_extra_fields {
    my ($s) = @_;

    if (ref($s) eq 'HASH' && defined $s->{type} && $s->{type} =~ m{/rec$}) {
        return {
            %$s,
            rest => '//any',
        }
    }
    return $s;
}

=func C<ignore_extra_fields_deep>

  my $rx_spec_lax = ignore_extra_fields_deep($rx_spec_strict);

Just like L</ignore_extra_fields>, but recurses through the entire
input data structure, maxing I<each> record specification "lax".

=cut

sub ignore_extra_fields_deep {
    my ($s) = @_;

    return Data::Visitor::Callback->new(
        hash => sub {ignore_extra_fields($_[1])},
    )->visit($s);
}
