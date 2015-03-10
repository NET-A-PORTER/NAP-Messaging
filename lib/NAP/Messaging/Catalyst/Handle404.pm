package NAP::Messaging::Catalyst::Handle404;
use NAP::policy;
use NAP::Messaging::Catalyst::Utils qw(extract_jms_headers type_and_destination stuff_on_error_queue);

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
    my ($type,$destination) = type_and_destination($ctx);

    $ctx->log->warn(
        "unhandled message: $type on $destination"
    );

    stuff_on_error_queue(
        undef,
        $ctx,'DLQ',
        404,
        [$message],
    );

    return;
}

## no critic (ProhibitMultiplePackages,ProhibitBuiltinHomonyms)

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
