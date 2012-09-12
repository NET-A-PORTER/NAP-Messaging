package NAP::Messaging::Role::Producer;
use NAP::policy 'role';
use List::MoreUtils ();
use NAP::Messaging::Validator;
use Data::Visitor::Callback;
use MooseX::ClassAttribute;

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

=head2 C<preprocessor>

A L<Data::Visitor::Callback> object, used to munge data returned by
the C<transform> method.

By default, it stringifies L<DateTime> objects with the format
C<%Y-%m-%dT%H:%M:%S.%3N%z>

=cut

has preprocessor => (
    isa         => 'Data::Visitor::Callback',
    is          => 'rw',
    builder     => '_build_preprocessor',
    required    => 1,
    lazy        => 1,
    clearer     => 'reset_default_preprocessor',
    handles     => {
        'preprocess_data' => 'visit',
    },
);

# request from Java for the format to be:
# yyyy-MM-dd'T'HH:mm:ss.SSSZ
sub _build_preprocessor {
    return Data::Visitor::Callback->new({
        'DateTime' => sub {
            if ($_->formatter) {
                return "$_";
            }
            # should be ISO8601
            return $_->strftime("%Y-%m-%dT%H:%M:%S.%3N%z");
        }
    })
}

=head1 METHODS

=head2 C<message_spec>

This method can return either a hashref describing the message as
specified in L<Data::Rx>, or a hashref with message types as keys, and
L<Data::Rx> description as values:

  sub message_spec { return { type => '//any' } }

or

  sub message_spec { return {
    SomeType => { type => '//any' },
    OtherType => { type => '//rec', ... } ,
  } }

If this method is not supplied, no validation will take place. If the
second form is used, trying to produce a message of a type not listed
will result in the validation failing.

NOTE: C<message_spec> must be a constant method. If you try to have it
return different values on different calls, the results are undefined.

=cut

class_has _message_validators => (
    isa => 'HashRef',
    is => 'ro',
    default => sub {
        my ($metaclass) = @_;
        # MooseX::ClassAttribute calls the default coderefs on the
        # metaclass; for normal attributes they're called on the
        # object. Let's try to make it work either way
        my $class = $metaclass->isa('Class::MOP::Package')
            ? $metaclass->name : $metaclass;
        my $specs= $class->can('message_spec')
            ? $class->message_spec : { type => '//any' };
        if ($specs->{type} && !ref($specs->{type})) {
            # looks like a single spec, use it as a default
            $specs = { '*' => $specs };
        }
        for my $spec (values %$specs) {
            $spec=NAP::Messaging::Validator->build_validator($spec);
        }
        return $specs;
    },
);

=head2 C<validate>

This method is called by L<Net::Stomp::Producer> to validate the
transformed message. It uses L</message_spec> to get the L<Data::Rx>
validation objects. You don't need to think about this method.

=cut

sub validate {
    my ($self,$headers,$body) = @_;

    if ($body->{'@type'}) { # legacy!
        require Storable;
        $body = Storable::dclone($body);
        delete $body->{'@type'};
    }

    my $validators = $self->_message_validators;
    my $msg_type = $headers->{type} // $headers->{JMStype};
    my $validator = $validators->{$msg_type} // $validators->{'*'};
    if (!$validator) {
        die NAP::Messaging::Exception::Validation->new({
            source_class => ref($self),
            data => $body,
            error => "No validation defined for $msg_type",
        });
    }
    my ($ok,$errs) = NAP::Messaging::Validator->validate($validator,$body);
    return 1 if $ok;
    die $errs;
}

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

Any C<destination>, be it defaulted from the L</destination>
attribute, or set by the C<transform> method, is mapped according to
the C<routes_map> configuration, via the L</map_destination> method.

The payloads are passed trough the L</preprocessor>.

=cut

requires 'transform';

around 'transform' => sub {
    my ($orig,$self,@args) = @_;

    my @rets = $self->$orig({},@args);
    my $conf = $self->_config;

    my $ret_it = List::MoreUtils::natatime 2,@rets;

    while (my ($header,$payload) = $ret_it->()) {
        my $dest = $self->map_destination(
            $header->{destination} // $self->destination
        );

        $header->{destination} = $dest;

        $header->{type} //= $self->type;
        # this will go away soon, I promise
        $payload->{'@type'} //= $header->{type};

        %$payload = %{$self->preprocess_data($payload)};
    }

    return @rets;
};

=method C<map_destination>

  my $destination = $self->map_destination($something);

Looks up C<$something> in the C<routes_map>, returns the corresponding
value, cleaned up via L</cleanup_destination>.

=cut

sub map_destination {
    my ($self,$destination) = @_;

    my $conf = $self->_config;
    if (exists $conf->{routes_map}{$destination}) {
        $destination = $conf->{routes_map}{$destination};
    }
    return $self->cleanup_destination($destination);
}

=method C<cleanup_destination>

  my $destination = $self->cleanup_destination($something);

If C<$something> starts with C</topic> or C</queue>, you get it back
unchanged. If it does not match C<^/?(?:topic|queue)>, it is prefixed
with C</queue>. The returned value always starts with C</>.

Please do not abuse this function: try to always set fully-qualified
destination names in you configuration!

=cut

sub cleanup_destination {
    my ($self,$destination) = @_;

    $destination =~ s{^/}{};
    if ($destination !~ m{^(?:topic|queue)}) {
        $destination = "queue/$destination";
    }
    $destination = "/$destination";
    return $destination;
}
