package NAP::Messaging::Catalyst::MessageQueueAdaptor;
use NAP::policy 'class';
extends 'CatalystX::ComponentsFromConfig::ModelAdaptor';
use NAP::Messaging::Serialiser;

# ABSTRACT: base class we use for our MessageQueue model

=head1 SYNOPSIS

In your config file:

  <Model::MessageQueue>
   base_class NAP::Messaging::Catalyst::MessageQueueAdaptor
   <args>
    <servers>
     hostname localhost
     port     61613
    </servers>
    <connect_headers>
     client-id myapp
    </connect_headers>
   </args>
  </Model::MessageQueue>

or, for testing:

  <Model::MessageQueue>
   base_class NAP::Messaging::Catalyst::MessageQueueAdaptor
   <args>
    <servers>
      hostname localhost
      port 61613
    </servers>
    trace_basedir t/tmp/amq_dump_dir
    trace 1
   </args>
   traits [ +Net::Stomp::MooseHelpers::TraceOnly ]
  </Model::MessageQueue>

=head1 DESCRIPTION

We use this adapter to avoid writing nearly-empty model classes, and
to make it easier to apply tracing roles.

We use L<NAP::Messaging::Serialiser> for serialisation, and we default
to persistent delivery. We pass the application's configuration to the
transformers' ("producers") constructors to allow
L<NAP::Messaging::Role::Producer> to map destinations via the config
file.

=cut

__PACKAGE__->config(
    class => 'Net::Stomp::Producer',
    args => {
        serializer => sub { NAP::Messaging::Serialiser->serialise($_[0]) },
        default_headers => {
            'content-type' => 'json',
            persistent => 'true',
        },
        transformer_args => {
        },
    },
);

around COMPONENT => sub {
    my ($orig, $class, $app, @rest) = @_;
    my $instance = $class->$orig($app,@rest);

    $instance->transformer_args->{_global_config} = $app->config;
    return $instance;
};
