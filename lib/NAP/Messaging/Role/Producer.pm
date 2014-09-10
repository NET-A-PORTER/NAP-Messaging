package NAP::Messaging::Role::Producer;
use NAP::policy 'role','tt';
use List::MoreUtils ();
use NAP::Messaging::Validator;
use NAP::Messaging::Exception::BadConfig;
use Data::Visitor::Callback;
use MooseX::ClassAttribute;
use Time::HiRes 'gettimeofday';

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
$header->{type} >>, or C<< $payload->{'@type'} >>, this role will do
it for you.

NOTE: C<< $payload->{'@type'} >> is a fossil, and will be removed
soon.

=head1 ATTRIBUTES

=cut

=head2 C<destination>

The name of an ActiveMQ destination to send messages to; can be
altered via L</routes_map>.

You can set this as show in the synopsis, or via the configuration, or
even leave it unset. If you do not provide a value for this attribute,
your L</transform> method I<must> assign a value to the C<destination>
slot in the header.

=cut

has destination => (
    is => 'ro',
    isa => 'Str',
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

=head2 C<routes_map>

Dictionary to map logical destination names to actual
destinations. Usually set in the configuration:

  <Producer::SomeType>
   <routes_map>
    SomeDestination  /queue/an_actual_queue
   </routes_map>
  </Producer::SomeType>

You can also do this:

  <Producer::SomeType>
   <routes_map>
    SomeDestination  /queue/an_actual_queue
    SomeDestination  /queue/another_queue
   </routes_map>
  </Producer::SomeType>

to get your producer to send each message to two different
destinations without altering the code.

You can even alter the type via the configuration:

  <Producer::SomeType>
   <routes_map>
    <SomeDestination /queue/an_actual_queue>
     SomeType real_type
    </SomeDestination>
    <SomeDestination /queue/another_queue>
     SomeType real_type1
     SomeType real_type2
    </SomeDestination>
   </routes_map>
  </Producer::SomeType>

That would send 3 messages:

=over 4

=item *

one of type C<real_type> to C</queue/an_actual_queue>

=item *

one of type C<real_type1> to C</queue/another_queue>

=item *

one of type C<real_type2> to C</queue/another_queue>

=back

Note: if L</set_at_type> is true, the C<@type> inside each message
will reflect the mapped type.

=cut

has routes_map => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} },
);

=head2 C<set_at_type>

For "backward compatibility", we default to set C<<
$payload->{'@type'} >>. This attribute controls that behaviour: set it
to a false value to I<not> set that field in the payload.

=cut

has set_at_type => (
    is => 'ro',
    isa => 'Bool',
    default => 1,
);

sub _config {
    my ($self,$global_config) = @_;

    my $class = ref($self) || $self;

    $class =~ s{^.*?::(?=Producer::)}{};

    if (exists $global_config->{$class}) {
        return $global_config->{$class};
    }
    return {}
}

around BUILDARGS => sub {
    my ($orig,$self,@args) = @_;
    my $args = $self->$orig(@args);
    my $config = $self->_config(delete $args->{_global_config});
    return { %$config,%$args };
};

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
    lazy => 1,
    builder => '_compile_validators',
);

sub _compile_validators {
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
}

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
the L</routes_map> attribute, via the L</map_destination> method.

Keep in mind that, if you did not provide a value for the
L</destination> attribute, and your C<transform> method does not set
the destination in the header, a
L<Net::Stomp::Producer::Exceptions::Invalid> will be thrown.

The payloads are passed trough the L</preprocessor>.

In the unlikely event you need to set the message type inside your
transformer, please use C<< $header->{type} >>, not C<JMSType>.

The header C<producer-timestamp> is set to the current epoch time, in
milliseconds. This, in conjuction with the C<timestamp> header that
the broker sets, and the timing logs provided by
L<NAP::Messaging::Timing> via L<NAP::Messaging::Role::ConsumesJMS>,
should help debug message propagation issues. Please keep in mind that
C<producer-timestamp> is set in this call, not when the message is
actually sent over the socket to the broker, so if you call C<<
->transform >> long before C<< ->send >>, your timing will be a bit
off.

=cut

requires 'transform';

around 'transform' => sub {
    my ($orig,$self,@args) = @_;

    my @pre_rets = $self->$orig({},@args);
    my $conf = $self->_config;
    my @rets;

    while (my ($header,$payload) = splice @pre_rets,0,2) {
        my $dest = $header->{destination} // $self->destination;

        if (!defined $dest) {
            Net::Stomp::Producer::Exceptions::Invalid->throw({
                transformer => ref($self),
                previous_exception => 'no previous exception',
                message_header => $header,
                message_body => $payload,
                reason => 'no destination defined, neither in the header nor in the producer/transformer attribute',
            });
        }

        if ($header->{JMSType} && !$header->{type}) {
            warn qq{$self set "JMSType" in the header. Please don't, and use "type".\n};
            $header->{type} = delete $header->{JMSType};
        }
        if ($header->{JMSType} && $header->{type}) {
            if ($header->{JMSType} eq $header->{type}) {
                warn qq{$self set both "JMSType" and "type" in the header, to the same value. Please use only "type".\n};
                delete $header->{JMSType};
            }
            else {
                Net::Stomp::Producer::Exceptions::Invalid->throw({
                    transformer => ref($self),
                    previous_exception => 'no previous exception',
                    message_header => $header,
                    message_body => $payload,
                    reason => qq{$self set both "JMSType" and "type" in the header, with different values. I give up},
                });
            }
        }
        $header->{type} //= $self->type;
        %$payload = %{$self->preprocess_data($payload)};

        # set the producer timestamp in the same format as the
        # 'timestamp' that the AMQ broker sets
        my ($secs,$usecs)=gettimeofday;
        $header->{'producer-timestamp'}=sprintf '%d%03d',$secs,$usecs/1000;

        my @dest_type_pairs = $self->map_destination_and_type($dest,$header->{type});

        for my $dt (@dest_type_pairs) {
            my %new_header = %$header;
            @new_header{qw(destination type)} = @$dt;

            if ($self->set_at_type) {
                require Storable;
                $payload = Storable::dclone($payload);
                # this will go away soon, I promise
                $payload->{'@type'} //= $header->{type};
            }

            push @rets, \%new_header,$payload;
        }
    }

    return @rets;
};

=method C<map_destination>

  my $destination = $self->map_destination($something);

Looks up C<$something> in the L</routes_map>, returns the
corresponding value, cleaned up via L</cleanup_destination>. If
L</routes_map> maps C<$something> to multiple destinations, a
L<NAP::Messaging::Exception::BadConfig> is thrown.

=cut

sub map_destination {
    my ($self,$destination) = @_;

    my @dest_type_pairs = $self->map_destination_and_type($destination,'*');
    my @dests = List::MoreUtils::uniq map { $_->[0] } @dest_type_pairs;
    if (@dests > 1) {
        NAP::Messaging::Exception::BadConfig->throw({
            transformer => ref($self),
            config_snippet => $self->routes_map,
            detail => "destination $destination maps to multiple real destinations, but the code called map_destination on it",
        });
    }
    return $dests[0];
}

=method C<map_destination_and_type>

  my @dest_type_pairs = $self->map_destination_and_type(
                                  $some_dest,
                                  $some_type,
                        );

Looks up C<$some_dest> and C<$some_type> in the L</routes_map>,
according to these rules:

=begin :list

* if L</routes_map> has no key C<$some_dest>, returns C<< [ $some_dest, $some_type ] >>
* if the value corresponding to C<$some_dest> is a string, returns C<< [ $the_value, $some_type ] >>
* if the value is an arrayref, returns C<< [ $array_elem, $some_type ] >> for each element of the array
* if the value is a hashref, the keys are taken to be destinations to map to, and for each of them (let's call it C<$dest_hash_key>):

=begin :list

* if the inner value is undef, returns C<< [ $dest_hash_key, $some_type ] >>
* if the inner value is a string, returns C<< [ $dest_hash_key, $the_inner_value ] >>
* if the inner value is an array, returns C<< [ $dest_hash_key, $array_elem] >> for each element of the array

=end :list

=end :list

All destination values are cleaned up via L</cleanup_destination>.

See L</routes_map> for some examples.

=cut

sub map_destination_and_type {
    my ($self,$destination,$type) = @_;

    my $conf = $self->_config;

    my @ret;
    if (not exists $self->routes_map->{$destination}) {
        @ret = [$destination,$type];
    }
    else {
        my $mapped_dest = $self->routes_map->{$destination};
        # one destination mapped to multiple destinations
        if (ref($mapped_dest) eq 'ARRAY') {
            @ret = map { [ $_, $type ] } @$mapped_dest;
        }
        # one destination mapped to multiple destinations, and types
        # mapped inside
        elsif (ref($mapped_dest) eq 'HASH') {
            for my $real_dest (keys %$mapped_dest) {
                my $type_map = $mapped_dest->{$real_dest};
                my $mapped_type = $type_map->{$type} // $type;
                # type mapped to multiple types
                if (ref($mapped_type) eq 'ARRAY') {
                    push @ret, map { [ $real_dest, $_ ] } @$mapped_type;
                }
                # type mapped to a single type
                else {
                    push @ret, [ $real_dest, $mapped_type ];
                }
            }
        }
        # one destinations mapped to a single destination
        else {
            @ret = [ $mapped_dest, $type ];
        }
    }

    return map { [$self->cleanup_destination($_->[0]),$_->[1]] } @ret;
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
