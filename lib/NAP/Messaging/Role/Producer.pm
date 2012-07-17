package NAP::Messaging::Role::Producer;
use NAP::policy 'role';
use List::MoreUtils ();

# ABSTRACT: role to help write ActiveMQ producers

=head1 SYNOPSIS

  package MyApp::Producer::SomeType;
  use NAP::policy 'class';
  with 'NAP::Messaging::Role::Producer';

  sub message_spec { return $some_data_rx_spec }

  has '+destination' => ( default => 'SomeDestination' );
  has '+type' => ( default => 'SomeType' );

  sub transform {
    my ($self,$header,@args) = @_;

    # do something to generate $payload

    return ($header,$payload);
  }

You should not need to set C<< $header->{destination} >>, C<<
$header->{type} >>, or C<< $payload->{'@type} >>, this role will do it
for you.

NOTE: C<< $payload->{'@type} >> is a fossil, and will be removed soon.

=head1 ATTRIBUTES

=cut

has _global_config => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { { } },
);

=head2 C<destination>

The name of an ActiveMQ destination to send messages to; can be
altered via configuration:

  <Producer::SomeType>
    <routes_map>
      SomeDestination  /queue/an_actual_queue
    </routes_map>
  </Producer::SomeType>

You must set this as shown in the synopsis.

=cut

has destination => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

=head2 C<type>

The message type. It will be used to set the C<type> header, and maybe
the C<@type> payload slot (we're going to deprecate it "soon").

You must set this as shown in the synopsis.

=cut

has type => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

sub _config {
    my ($self) = @_;

    my $class = ref($self) || $self;

    $class =~ s{^.*?::(?=Producer::)}{};

    if (exists $self->_global_config->{$class}) {
        return $self->_global_config->{$class};
    }
    return {}
}

=head1 METHODS

=head2 C<transform>

As shown in the synopsis, this method gets a "header template" (a hash
ref), and whatever arguments were passed to the
L<Net::Stomp::Producer> C<transform_and_send> method. It is expected
to return a list of pairs C<$msg_header, $msg_payload> of messages to
send.

For example:

   $c->model('MessageQueue')->transform_and_send(
     'MyApp::Producer::SomeType',
     $val1,$val2,
   );

will call (more or less):

  MyApp::Producer::SomeType->new()->transform(
    $header,
    $val1, $val2,
  );

The returned headers need not include a C<destination> or C<type>
value, and the returned payloads needs not include a C<@type> value.

=cut

requires 'transform';

around 'transform' => sub {
    my ($orig,$self,@args) = @_;

    my @rets = $self->$orig({},@args);
    my $conf = $self->_config;

    my $ret_it = List::MoreUtils::natatime 2,@rets;

    while (my ($header,$payload) = $ret_it->()) {
        my $dest = $header->{destination} // $self->destination;

        if (exists $conf->{routes_map}{$dest}) {
            $dest = $conf->{routes_map}{$dest};
        }

        $dest =~ s{^/}{};
        if ($dest !~ m{^(?:topic|queue)}) {
            $dest = "queue/$dest";
        }
        $dest = "/$dest";

        $header->{destination} = $dest;

        $header->{type} //= $self->type;
        # this will go away soon, I promise
        $payload->{'@type'} //= $self->type;
    }

    return @rets;
};
