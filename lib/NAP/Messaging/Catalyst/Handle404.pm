package NAP::Messaging::Catalyst::Handle404;
use NAP::Messaging::Catalyst::Utils qw(extract_jms_headers stuff_on_error_queue);

# ABSTRACT: function and roles to put unknown messages into a DLQ

=head1 DESCRIPTION

This is an internal package, used by
L<NAP::Messaging::Role::ConsumesJMS> and
L<NAP::Messaging::Catalyst::Controller::Root>.

=method C<handle404>

Given a context and a string, puts a "404" message in a DLQ.

=cut

sub handle404 {
    my ( $self, $ctx, $message ) = @_;
    $ctx->response->status(404);

    $ctx->stash->{headers} = extract_jms_headers($ctx);

    $ctx->log->warn(
          q{unhandled message: }
        . ($ctx->stash->{headers}{type} // '(untyped)')
        . " on ".$ctx->request->uri->path
    );

    stuff_on_error_queue(
        undef,
        $ctx,'DLQ',
        404,
        [$message],
    );

    return;
}

package NAP::Messaging::Catalyst::Handle404::RootRole {
    use NAP::policy 'role';
    use MooseX::MethodAttributes::Role;

    sub default : Private {
        my ( $self, $ctx ) = @_;
        return NAP::Messaging::Catalyst::Handle404::handle404(
            $self,$ctx,
            'unknown destination',
        );
    }
}

package NAP::Messaging::Catalyst::Handle404::ConsumerRole {
    use NAP::policy 'role';
    use MooseX::MethodAttributes::Role;

    sub default : Private {
        my ( $self, $ctx ) = @_;
        return NAP::Messaging::Catalyst::Handle404::handle404(
            $self,$ctx,
            'unknown message type',
        );
    }
}
