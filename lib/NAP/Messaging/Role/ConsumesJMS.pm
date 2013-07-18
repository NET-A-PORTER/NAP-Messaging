package NAP::Messaging::Role::ConsumesJMS;
use NAP::policy 'role','tt';
with 'CatalystX::ConsumesJMS';
use NAP::Messaging::Validator;
use NAP::Messaging::Catalyst::Utils qw(extract_jms_headers type_and_destination stuff_on_error_queue);
require NAP::Messaging::Catalyst::Handle404;
use Scalar::Util qw(openhandle);

# ABSTRACT: role for NAP consumer base classes

=head1 SYNOPSIS

  package MyApp::Base::Stuff;
  use NAP::policy 'class';
  with 'NAP::Messaging::Role::ConsumesJMS';

  sub _kind_name {'Stuff'}
  sub _wrap_coderef { return $_[2] }

Then:

  package MyApp::Stuff::One;
  use NAP::policy 'class';
  extends 'MyApp::Base::Stuff';

  sub routes {
    return {
      my_input_queue => {
        my_message_type => {
          spec => { type => '//any },
          code => \&my_consume_method,
        },
        ...
      },
      ...
    }
  }

  sub my_consume_method {
    my ($self,$ctx,$message,$headers) = @_;

    # do something
  }

=head1 DESCRIPTION

This role is to be used in things like
L<NAP::Messaging::Base::Consumer>, that need to map application
components to Catalyst controllers. It's I<not> to be consumed
directly by application components. It's a specialisation of
L<CatalystX::ConsumesJMS> to add NAP-specific validation and error
handling. See L<CatalystX::ConsumesJMS> for details on routing.

=head2 The spec

The value paired to the C<spec> key should be a hashref describing the
message as specified in L<Data::Rx>. The top-level type must be
C<//rec>. If a message is received (in that queue with that type) that
does not conform to this description, the message will be rejected.

=head2 The "code"

The coderef paired to the C<code> key will be wrapped via the
L</_wrap_coderef> function that the consuming class has to provide.

The coderef so wrapped will be invoked as a method on the subclass
object, passing:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=item *

the (validated) de-serialized message

=item *

the request headers (a hashref)

=back

=cut

requires '_wrap_coderef';

=head1 Implementation Details

Our C<_wrap_code> provides header munging and payload validation:

=over 4

=cut

my $slurp_body = sub {
   my ($body) = @_;
   my $rbody;
   if (openhandle $body) {
       seek($body, 0, 0); # in case something has already read from it
       while ( defined( my $line = <$body> ) ) {
           $rbody .= $line;
       }
   } else {
       $rbody = $body;
   }
   return $rbody;
};

sub _wrap_code {
    my ($self,$c,$destination_name,$msg_type,$route) = @_;

=item *

the C<spec> value is converted to a C<Data::Rx> schema via
L<NAP::Messaging::Validator>

=cut

    my $code = $route->{code};
    my $spec = $route->{spec};
    my $validator = NAP::Messaging::Validator->build_validator($spec);
    my $sub_wrapped_code = $self->_wrap_coderef($c,$code);
    return sub {
        my ($controller,$ctx) = @_;
        my $message = $ctx->req->data;

=item *

JMS-specific values from the L<PSGI> request are extracted into a
hashref, stored in C<< ->stash->{headers} >> (see
L<Plack::Handler::Stomp> for details)

=cut

        $ctx->stash->{headers} = extract_jms_headers($ctx);
        my ($type,$destination) = type_and_destination($ctx);

        my $error_prefix = "message of type $type on $destination";

=item *

if the message payload failed to de-serialise, the error is logged,
and we call L</handle_validation_failure>.

=cut

        if (!defined $message) {
            my $err = $ctx->stash->{deserialise_error};
            $err ||= "the message had no deserialisable payload";

            $ctx->log->error("$error_prefix failed deserialisation: $err");
            $ctx->response->status(400);
            my $body = $slurp_body->($ctx->request->body);
            $ctx->request->data($body);
            $self->handle_validation_failure($ctx,$err);
            return;
        }

=item *

the message payload is validated against the schema built above; if it
fails, the error is logged, and we call L</handle_validation_failure>.

=cut

        delete $message->{'@type'};
        my ($ok,$validation_errors) = NAP::Messaging::Validator->validate(
            $validator,$message);
        if (!$ok) {
            $ctx->log->error("$error_prefix failed validation: $validation_errors");
            $ctx->response->status(400);
            $self->handle_validation_failure($ctx,$validation_errors);
            return;
        }

=item *

if instead the message validates, we call the consume method (wrapped
by C<_wrap_coderef>) passing C< $ctx, $message, \%headers >.

The call is done in a C<try> block; if the method dies, the error is
logged, we set the exception as a possible reply, and call
L</handle_processing_failure>.

=cut

        try {
            $controller->$sub_wrapped_code($ctx,$message,$ctx->stash->{headers});
        }
        catch {
            $ctx->log->error("$error_prefix failed processing: $_");
            $ctx->response->status(500);
            $ctx->stash->{message} = $_;
            $self->handle_processing_failure($ctx,$_);
        };
        return;
    };
}

=back

=head2 C<handle_validation_failure>

Calls
L<stuff_on_error_queue|NAP::Messaging::Catalyst::Utils/stuff_on_error_queue>
with a prefix of C<'DLQ.failed-validation'>

=cut

sub handle_validation_failure {
    my ($self,$ctx,$validation_errors) = @_;

    stuff_on_error_queue(
        $self,
        $ctx,'DLQ.failed-validation',
        400,
        ["$validation_errors"],
    );
    return;
}

=head2 C<handle_processing_failure>

Calls
L<stuff_on_error_queue|NAP::Messaging::Catalyst::Utils/stuff_on_error_queue>
with a prefix of C<'DLQ'>

=cut

sub handle_processing_failure {
    my ($self,$ctx,$exception) = @_;

    stuff_on_error_queue(
        $self,
        $ctx,'DLQ',
        500,
        ["$exception"],
    );
    return;
}

=head2 C<_controller_base_classes>

We set the base class to L<NAP::Messaging::Catalyst::Controller::JMS>,
to catch de-serialsation failures in a way that allows us to send them
to a DLQ.

=cut

sub _controller_base_classes { 'NAP::Messaging::Catalyst::Controller::JMS' }

=head2 C<_controller_roles>

We apply
L<NAP::Messaging::Catalyst::Handle404::ConsumerRole|NAP::Messaging::Catalyst::Handle404>
to throw unhandled messages to the DLQ.

=cut

sub _controller_roles { 'NAP::Messaging::Catalyst::Handle404::ConsumerRole' }
