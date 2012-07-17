package NAP::Messaging::Role::ConsumesJMS;
use NAP::policy 'role';
with 'CatalystX::ConsumesJMS';
use NAP::Messaging::Validator;

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

        # this might not be the cleanest way of doing it, see
        # Plack::Handler::Stomp to see where these values come from
        my $psgi_env = $ctx->req->can('env') ? $ctx->req->env : $ctx->engine->env;
        my %headers = map { s/^jms\.//r, $psgi_env->{$_} }
            grep { /^jms\./ } keys %$psgi_env;
        $ctx->stash->{headers}=\%headers;

=item *

the message payload is validated against the schema built above; if it
fails, the error is logged, we call L</stuff_on_error_queue> with a
prefix of C<'DLQ.failed-validation'>

=cut

        delete $message->{'@type'};
        my ($ok,$validation_errors) = NAP::Messaging::Validator->validate(
            $validator,$message);
        if (!$ok) {
            $ctx->log->error("$validation_errors");
            $ctx->response->status(500);
            $self->stuff_on_error_queue(
                $ctx,'DLQ.failed-validation',
                500,
                ["$validation_errors"],
            );
            return;
        }

=item *

if instead the message validates, we call the consume method (wrapped
by C<_wrap_coderef>) passing C< $ctx, $message, \%headers >.

The call is done in a C<try> block; if the method dies, we set the
exception as a possible reply, and call C<stuff_on_error_queue> with a
prefix of C<'DLQ'>

=cut

        try {
            $controller->$sub_wrapped_code($ctx,$message,\%headers);
        }
        catch ($e) {
            $ctx->response->status(400);
            $ctx->stash->{message} = $e;
            $self->stuff_on_error_queue(
                $ctx,'DLQ',
                $ctx->response->status,
                ["$e"],
            );
        }
        return;
    };
}

=back

=method C<stuff_on_error_queue>

  $component->stuff_on_error_queue($ctx,$prefix,$status,$errors);

Expects:

=for :list
* C<< $ctx->req->data >> to be the payload of the message causing the problem
* C<< $ctx->stash->{headers} >> to be the headers of that same message
* C<< $ctx->req->path >> to be a STOMP-ish destination
* C<< $ctx->model('MessageQueue') >> to be have a C<send> method like L<Net::Stomp::Producer>

It will then prepare a message with a payload like:

  {
    original_message => $ctx->req->data,
    original_headers => $ctx->stash->{headers},
    consumer => ref($component),
    destination => $ctx->req->uri->as_string,
    method => $ctx->req->method,
    ( defined $errors ? ( errors => $errors ) : () ),
    ( defined $status ? ( status => $status ) : () ),
  }

and it will send it to a queue called C<
${prefix}.${original_destination} >. The message will have type C<
error-${original_type} >.

=cut

sub stuff_on_error_queue {
    my ($self,$ctx,$prefix,$status,$errors) = @_;

    my $payload = {
        original_message => $ctx->req->data,
        original_headers => $ctx->stash->{headers},
        consumer => ref($self),
        destination => $ctx->req->uri->as_string,
        method => $ctx->req->method,
        ( defined $errors ? ( errors => $errors ) : () ),
        ( defined $status ? ( status => $status ) : () ),
    };
    my $path = $ctx->req->path;$path=~s{^/+}{};
    my $destination = "/queue/${prefix}.${path}";

    $ctx->model('MessageQueue')->send(
        $destination,
        {
            type => 'error-'.$ctx->stash->{headers}{type},
        },
        $payload);
}
