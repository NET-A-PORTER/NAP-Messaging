package NAP::Messaging::Catalyst::Utils;
use NAP::policy 'exporter','tt';
use Sub::Exporter -setup => {
    exports => [ qw(extract_jms_headers type_and_destination stuff_on_error_queue) ],
};

# ABSTRACT: some common utilities that don't fit in classes / roles

=func C<extract_jms_headers>

  my $headers = extract_jms_headers($ctx);

Extracts the JMS-related header values from the PSGI environment. See
L<Plack::Handler::Stomp> for details.

=cut

sub extract_jms_headers {
    my ($ctx) = @_;

    # this might not be the cleanest way of doing it, see
    # Plack::Handler::Stomp to see where these values come from
    my $psgi_env = $ctx->req->can('env') ? $ctx->req->env : $ctx->engine->env;
    my %headers = map { s/^jms\.//r, $psgi_env->{$_} }
        grep { /^jms\./ } keys %$psgi_env;
    return \%headers;
}

=func C<type_and_destination>

  my ($type,$destination) = type_and_destination($ctx);

NOTE: this function expects you have run:

    $ctx->stash->{headers} = extract_jms_headers($ctx);

at some point during the current request, before calling this
function.

Returns the message type and the destination, for the current request.

=cut

sub type_and_destination {
    my ($ctx) = @_;

    my $type = $ctx->stash->{headers}{type} //
        $ctx->stash->{headers}{JMSType} //
            '<unknown type>';
    my $destination = $ctx->req->uri->path //
        $ctx->stash->{headers}{destination} //
            '<unknown destination>';
    return ($type,$destination);
}

=func C<stuff_on_error_queue>

  stuff_on_error_queue($component,$ctx,$prefix,$status,$errors);

Expects:

=for :list
* C<< $ctx->req->data >> to be the payload of the message causing the problem
* C<< $ctx->stash->{headers} >> to be the headers of that same message
* C<< $ctx->req->path >> to be a STOMP-ish destination
* C<< $ctx->model('MessageQueue') >> to have a C<send> method like L<Net::Stomp::Producer>

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
    my ($component,$ctx,$prefix,$status,$errors) = @_;

    my $payload = {
        original_message => $ctx->req->data,
        original_headers => $ctx->stash->{headers},
        consumer => ref($component) || $component,
        destination => $ctx->req->uri->path,
        method => $ctx->req->method,
        ( defined $errors ? ( errors => $errors ) : () ),
        ( defined $status ? ( status => $status ) : () ),
    };
    my $path = $ctx->req->path;$path=~s{^/+}{};
    my $destination = "/queue/${prefix}.${path}";

    $ctx->model('MessageQueue')->send(
        $destination,
        {
            type => 'error-'.($ctx->stash->{headers}{type}//'unknown'),
        },
        $payload);

    return;
}
