package NAP::Messaging;
## no critic
# ABSTRACT: documentation for the NAP Perl messaging framework
warn "why are you using a documentation-only package?";
1;
__END__

=head1 DESCRIPTION

This framework makes it decently easy to define JMS / ActiveMQ
consumer applications, and to produce messages to be sent.

=head1 A SAMPLE CONSUMER APPLICATION

Application class:

  package MyApp;
  use NAP::policy 'class';
  extends 'NAP::Messaging::Catalyst';
  __PACKAGE__->setup();

Consumer component:

  package MyApp::Consumer::One;
  use NAP::policy 'class';
  extends 'NAP::Messaging::Base::Consumer';

  sub routes {
    return {
      my_input_queue => {
        my_message_type => {
          spec => {
            type => '//rec',
            required => { count => '//int'},
          },
          code => \&my_consume_method,
        },
      },
    }
  }

  sub my_consume_method {
    my ($self,$message,$headers) = @_;

    # on receiving the message, send a new message
    $self->amq->transform_and_send('MyApp::Producer::Foo',{
      count => $message->{count} + 1,
    })
  }

The producer:

  package MyApp::Producer::Foo;
  use NAP::policy 'class';
  with 'NAP::Messaging::Role::Producer';

  sub message_spec {
    return {
      type => '//rec',
      required => { value => '//int'}
    }
  }
  has '+destination' => ( default => 'my_destination' );
  has '+type' => ( default => 'my_response' );

  sub transform {
    my ($self,$header,$arg) = @_;

    return ($header, { value => $arg->{count} });
  }

Configuration:

  log4perl log4perl.conf
  <log4perlopts>
   autoflush 1
  </log4perlopts>

  <stacktrace>
   enable 1
  </stacktrace>

  <setup_components>
   search_extra [ ::Consumer ]
  </setup_components>

  <Plugin::ErrorCatcher>
   enable 1
  </Plugin::ErrorCatcher>

  <Stomp>
   <connect_headers>
    client-id myapp
   </connect_headers>
   <subscribe_headers>
    activemq.exclusive false
    activemq.prefetchSize 1
   </subscribe_headers>
  </Stomp>

  <Model::MessageQueue>
   base_class NAP::Messaging::Catalyst::MessageQueueAdaptor
   <args>
    <servers>
     hostname localhost
     port     61613
    </servers>
    <connect_headers>
     client-id myapp-sending
    </connect_headers>
   </args>
  </Model::MessageQueue>

  <Consumer::One>
   <routes_map>
    my_input_queue queue/the_actual_queue_name
   </routes_map>
  </Consumer::One>

  <Producer::Foo>
   <routes_map>
    my_destination queue/the_actual_destination
   </routes_map>
  </Producer::Foo>

The script to run it:

  #!perl
  use NAP::policy;
  use Plack::Handler::Stomp;
  use MyApp qw();

  my $servers = MyApp->model('MessageQueue')
     ->servers;

  my @subscriptions = map {; {
      destination => $_,
  } } MyApp->jms_destinations;

  my $handler = Plack::Handler::Stomp->new({
    %{ MyApp->config->{Stomp} // {} },
    servers => $servers,
    subscriptions => \@subscriptions,
    logger => MyApp->log,
  });

  $handler->run(MyApp->psgi_app);

=head1 IN-DEPTH DOCS

=for :list
* L<NAP::Messaging::Catalyst> for the base application
* L<NAP::Messaging::Base::Consumer> for the consumer components
* L<NAP::Messaging::Catalyst::MessageQueueAdaptor> for the producer config
* L<NAP::Messaging::Role::Producer> for the producer helper
* L<NAP::Messaging::Validator> for incoming / outgoing message validation
* L<Test::NAP::Messaging> for testing applications
