# Declare our package
package POE::Component::Server::SimpleHTTP;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.04';

# Import what we need from the POE namespace
use POE;			# For the constants
use POE::Session;		# To create our own :)

# Other miscellaneous modules we need
use Carp;

# HTTP-related modules
use HTTP::Date;
use Socket qw( inet_ntoa );

# Our own HTTP modules
use POE::Component::Server::SimpleHTTP::Connection;
use POE::Component::Server::SimpleHTTP::Request;
use POE::Component::Server::SimpleHTTP::Response;

# POE modules to handle the connection
use POE::Wheel::ReadWrite;
use POE::Driver::SysRW;
use POE::Filter::Stream;
use POE::Filter::HTTPD;
use POE::Component::Server::TCP;

# Set some constants
BEGIN {
	# Debug fun!
	if ( ! defined &DEBUG ) {
		eval "sub DEBUG () { 0 }";
	}
}

# Set things in motion!
sub new {
	# Get the OOP's type
	my $type = shift;

	# Sanity checking
	if ( @_ & 1 ) {
		croak( 'POE::Component::Server::SimpleHTTP->new needs even number of options' );
	}

	# The options hash
	my %opt = @_;

	# Our own options
	my ( $ALIAS, $ADDRESS, $PORT, $HOSTNAME, $HEADERS, $HANDLERS );

	# You could say I should do this: $Stuff = delete $opt{'Stuff'}
	# But, that kind of behavior is not defined, so I would not trust it...

	# Get the session alias
	if ( exists $opt{'ALIAS'} ) {
		$ALIAS = $opt{'ALIAS'};
		delete $opt{'ALIAS'};
	} else {
		# Debugging info...
		if ( DEBUG ) {
			warn 'Using default ALIAS = SimpleHTTP';
		}

		# Set the default
		$ALIAS = 'SimpleHTTP';
	}

	# Get the PORT
	if ( exists $opt{'PORT'} ) {
		$PORT = $opt{'PORT'};
		delete $opt{'PORT'};
	} else {
		croak( 'PORT is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Get the ADDRESS
	if ( exists $opt{'ADDRESS'} ) {
		$ADDRESS = $opt{'ADDRESS'};
		delete $opt{'ADDRESS'};
	} else {
		croak( 'ADDRESS is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Get the HOSTNAME
	if ( exists $opt{'HOSTNAME'} ) {
		$HOSTNAME = $opt{'HOSTNAME'};
		delete $opt{'HOSTNAME'};
	} else {
		if ( DEBUG ) {
			warn 'Using Sys::Hostname for HOSTNAME';
		}

		# Figure out the hostname
		require Sys::Hostname;
		$HOSTNAME = Sys::Hostname::hostname();
	}

	# Get the HEADERS
	if ( exists $opt{'HEADERS'} ) {
		# Make sure it is ref to hash
		if ( ref( $opt{'HEADERS'} ) and ref( $opt{'HEADERS'} ) eq 'HASH' ) {
			$HEADERS = $opt{'HEADERS'};
			delete $opt{'HEADERS'};
		} else {
			croak( 'HEADERS must be a reference to a HASH!' );
		}
	} else {
		# Set to none
		$HEADERS = {};
	}

	# Get the HANDLERS
	if ( exists $opt{'HANDLERS'} ) {
		# Make sure it is ref to array
		if ( ref( $opt{'HANDLERS'} ) and ref( $opt{'HANDLERS'} ) eq 'ARRAY' ) {
			$HANDLERS = $opt{'HANDLERS'};
			delete $opt{'HANDLERS'};
		} else {
			croak( 'HANDLERS must be a reference to an ARRAY!' );
		}
	} else {
		croak( 'HANDLERS is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Create a new session for ourself
	POE::Session->create(
		# Our subroutines
		'inline_states'	=>	{
			# Maintenance events
			'_start'	=>	\&StartServer,
			'_stop'		=>	sub {},
			'_child'	=>	sub {},

			# HANDLER stuff
			'GETHANDLERS'	=>	\&GetHandlers,
			'SETHANDLERS'	=>	\&SetHandlers,

			# Shutdown event
			'SHUTDOWN'	=>	\&StopServer,

			# Wheel::ReadWrite stuff
			'Got_Connection'	=>	\&Got_Connection,
			'Got_Input'		=>	\&Got_Input,
			'Got_Flush'		=>	\&Got_Flush,
			'Got_Error'		=>	\&Got_Error,

			# Send output to connection!
			'DONE'		=>	\&Got_Output,
		},

		# Set up the heap for ourself
		'heap'		=>	{
			'ALIAS'		=>	$ALIAS,
			'ADDRESS'	=>	$ADDRESS,
			'PORT'		=>	$PORT,
			'HEADERS'	=>	$HEADERS,
			'HOSTNAME'	=>	$HOSTNAME,
			'HANDLERS'	=>	$HANDLERS,
		},
	) or die 'Unable to create a new session!';

	# Return success
	return 1;
}

# Gets the HANDLERS
sub GetHandlers {
	# ARG0 = session, ARG1 = event
	my( $session, $event ) = @_[ ARG0, ARG1 ];

	# Validation
	if ( ! defined $session or ! defined $event ) {
		return undef;
	}

	# Make a deep copy of the handlers
	require Storable;

	my $handlers = Storable::dclone( $_[HEAP]->{'HANDLERS'} );

	# Remove the RE part
	foreach my $ary ( @$handlers ) {
		delete $ary->{'RE'};
	}

	# All done!
	$_[KERNEL]->post( $_[ARG0], $_[ARG1], $handlers );
}

# Sets the HANDLERS
sub SetHandlers {
	# ARG0 = ref to handlers array
	my $handlers = $_[ARG0];

	# Validate it...
	MassageHandlers( $handlers );

	# If we got here, passed tests!
	$_[HEAP]->{'HANDLERS'} = $handlers;
}

# Starts the server!
sub StartServer {
	# Register an alias for ourself
	$_[KERNEL]->alias_set( $_[HEAP]->{'ALIAS'} );

	# Massage the handlers!
	MassageHandlers( $_[HEAP]->{'HANDLERS'} );

	# Set up the HTTPD Daemon!
	POE::Component::Server::TCP->new(
		# Stuff to set up the port
		'Address'	=>	$_[HEAP]->{'ADDRESS'},
		'Port'		=>	$_[HEAP]->{'PORT'},

		# Set the alias so we can destroy it later
		'Alias'		=>	$_[HEAP]->{'ALIAS'} . '_TCP',

		# Receive connections and handle them ourself!
		'Acceptor'	=>	\&Acceptor,
	);

	# All done!
	return 1;
}

# This subroutine massages the HANDLERS for internal use
sub MassageHandlers {
	# Get the ref to handlers
	my $handler = shift;

	# Make sure it is ref to array
	if ( ! ref( $handler ) or ref( $handler ) ne 'ARRAY' ) {
		croak( "HANDLERS is not a ref to an array!" );
	}

	# Massage the handlers
	my $count = 0;
	while ( $count < scalar( @$handler ) ) {
		# Must be ref to hash
		if ( ref( $handler->[ $count ] ) and ref( $handler->[ $count ] ) eq 'HASH' ) {
			# Make sure it got the 3 parts necessary
			if ( ! exists $handler->[ $count ]->{'SESSION'} or ! defined $handler->[ $count ]->{'SESSION'} ) {
				croak( "HANDLER number $count does not have a SESSION argument!" );
			}
			if ( ! exists $handler->[ $count ]->{'EVENT'} or ! defined $handler->[ $count ]->{'EVENT'} ) {
				croak( "HANDLER number $count does not have an EVENT argument!" );
			}
			if ( ! exists $handler->[ $count ]->{'DIR'} or ! defined $handler->[ $count ]->{'DIR'} ) {
				croak( "HANDLER number $count does not have a DIR argument!" );
			}

			# Convert SESSION to ID
			if ( UNIVERSAL::isa( $handler->[ $count ]->{'SESSION'}, 'POE::Session') ) {
				$handler->[ $count ]->{'SESSION'} = $handler->[ $count ]->{'SESSION'}->ID;
			}

			# Convert DIR to qr// format
			my $regex = undef;
			eval { $regex = qr/$handler->[ $count ]->{'DIR'}/ };

			# Check for errors
			if ( $@ ) {
				croak( "HANDLER number $count has a malformed DIR -> $@" );
			} else {
				# Store it!
				$handler->[ $count ]->{'RE'} = $regex;
			}
		} else {
			croak( "HANDLER number $count is not a reference to a HASH!" );
		}

		# Done with this one!
		$count++;
	}
}

# Stops the server!
sub StopServer {
	# Tell our TCP counterpart to die!
	$_[KERNEL]->call( $_[HEAP]->{'ALIAS'} . '_TCP', 'shutdown' );

	# Forcibly close all sockets that are open
	foreach my $conn ( @{ $_[HEAP]->{'WHEELS'} } ) {
		$conn->[0]->shutdown_input;
		$conn->[0]->shutdown_output;
	}

	# Delete our alias
	$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );

	# Remove all connections
	delete $_[HEAP]->{'WHEELS'};

	# Return success
	return 1;
}

# Accepts new connections
sub Acceptor {
	# ARG0 = Socket, ARG1 = Remote Address, ARG2 = Remote Port

	# Send to the main server session
	if ( $_[HEAP]->{'alias'} =~ /^(.*)\_TCP$/ ) {
		my $parent = $1;
		$_[KERNEL]->post( $1, 'Got_Connection', $_[ ARG0 ], $_[ ARG1 ], $_[ ARG2 ] );
	} else {
		die 'Unable to get the parent alias!';
	}

	# Debug stuff
	if ( DEBUG ) {
		warn 'Acceptor got connection, sending to parent';
	}
}

# The actual manager of connections
sub Got_Connection {
	# ARG0 = Socket, ARG1 = Remote Address, ARG2 = Remote Port
	my( $socket, $remote_address, $remote_port ) = @_[ ARG0 .. ARG2 ];

	# Create the connection object
	my $connection = POE::Component::Server::SimpleHTTP::Connection->new(
		inet_ntoa( $remote_address ),
		$remote_port,
		getpeername( $socket ),
		getsockname( $socket )
	);

	# Set up the Wheel to read from the socket
	my $wheel = POE::Wheel::ReadWrite->new(
		'Handle'	=>	$socket,
		'Driver'	=>	POE::Driver::SysRW->new(),
		'Filter'	=>	POE::Filter::HTTPD->new(),
		'InputEvent'	=>	'Got_Input',
		'FlushedEvent'	=>	'Got_Flush',
		'ErrorEvent'	=>	'Got_Error',
	);

	# Save this wheel!
	# 0 = wheel, 1 = connection, 2 = Output done?
	$_[HEAP]->{'WHEELS'}->{ $wheel->ID } = [ $wheel, $connection, 0 ];

	# Debug stuff
	if ( DEBUG ) {
		warn "Got_Connection completed creation of ReadWrite wheel ( " . $wheel->ID . " )";
	}
}

# Finally got input, set some stuff and send away!
sub Got_Input {
	# ARG0 = HTTP::Request object, ARG1 = Wheel ID
	my( $request, $id ) = @_[ ARG0, ARG1 ];

	# Change the HTTP::Request object to our stuff!
	bless( $request, 'POE::Component::Server::SimpleHTTP::Request' );

	# Get the connection
	my $c = $_[HEAP]->{'WHEELS'}->{ $id }->[1];

	# Add stuff it needs!
	my $uri = $request->uri;
	$uri->scheme( 'http' );
	$uri->host( $_[HEAP]->{'HOSTNAME'} );
	$uri->port( $_[HEAP]->{'PORT'} );
	$request->_Connection( $c );

	# Get the path
	my $path = $uri->path();
	if ( ! defined $path or $path eq '' ) {
		# Make it the default handler
		$path = '/';
	}

	# Get the response
	my $response = POE::Component::Server::SimpleHTTP::Response->new( $id );

	# Stuff the default headers
	$response->header( %{ $_[HEAP]->{'HEADERS'} } );

	# Find which handler will handle this one
	foreach my $handler ( @{ $_[HEAP]->{'HANDLERS'} } ) {
		# Check if this matches
		if ( $path =~ $handler->{'RE'} ) {
			# Send this off!
			$_[KERNEL]->post(	$handler->{'SESSION'},
						$handler->{'EVENT'},
						$request,
						$response,
						$handler->{'DIR'},
			);

			# All done!
			return undef;
		}
	}

	# If we reached here, no handler was able to handle it...
	die 'No handler was able to handle ' . $path;
}

# Finished with a wheel!
sub Got_Flush {
	# ARG0 = wheel ID
	my $id = $_[ ARG0 ];

	# Debug stuff
	if ( DEBUG ) {
		warn "Got Flush event for wheel ID ( $id )";
	}

	# Check if we are shutting down
	if ( $_[HEAP]->{'WHEELS'}->{ $id }->[2] ) {
		# Delete the wheel
		delete $_[HEAP]->{'WHEELS'}->{ $id };
	} else {
		# Ignore this, eh?
		if ( DEBUG ) {
			warn "Got Flush event for socket ( $id ) when did not send anything!";
		}
	}
}

# Output to the client!
sub Got_Output {
	# ARG0 = HTTP::Response object or ref to string
	my $response = $_[ ARG0 ];

	# Check if we got it
	if ( ! defined $response or ! UNIVERSAL::isa( $response, 'HTTP::Response' ) ) {
		if ( DEBUG ) {
			warn 'Did not get a HTTP::Response object!';
		}

		# Abort...
		return undef;
	}

	# Check if we have already sent the response
	my $wheel = $response->_WHEEL;
	if ( $_[HEAP]->{'WHEELS'}->{ $wheel }->[2] ) {
		# Tried to send twice!
		die 'Tried to send a response to the same connection twice!';
	}

	# Set the date if needed
	if ( ! $response->header( 'Date' ) ) {
		$response->header( 'Date', time2str( time ) );
	}

	# Set the Content-Length if needed
	if ( ! $response->header( 'Content-Length' ) ) {
		$response->header( 'Content-Length', length( $response->content ) );
	}

	# Set the Content-Type if needed
	if ( ! $response->header( 'Content-Type' ) ) {
		$response->header( 'Content-Type', 'text/html' );
	}

	# Send it out!
	# Bug reported by Tim Wood
	eval { $_[HEAP]->{'WHEELS'}->{ $wheel }->[0]->put( $response ) };
	if ( $@ ) {
		if ( DEBUG ) {
			warn 'Tried to send data over a closed/nonexistant socket!';
		}
	}

	# Mark this socket done
	$_[HEAP]->{'WHEELS'}->{ $wheel }->[2] = 1;

	# Debug stuff
	if ( DEBUG ) {
		warn "Completed with Wheel ID $wheel";
	}
}

# Got some sort of error from ReadWrite
sub Got_Error {
	# ARG0 = operation, ARG1 = error number, ARG2 = error string, ARG3 = wheel ID
	my ( $operation, $errnum, $errstr, $wheel_id ) = @_[ ARG0 .. ARG3 ];

	# Debug stuff
	if ( DEBUG ) {
		warn "Wheel $wheel_id generated $operation error $errnum: $errstr\n";
	}

	# Delete this connection
	delete $_[HEAP]->{'WHEELS'}->{ $wheel_id };
}

# End of module
1;

__END__

=head1 NAME

POE::Component::Server::SimpleHTTP - Perl extension to serve HTTP requests in POE.

=head1 SYNOPSIS

	use POE;
	use POE::Component::Server::SimpleHTTP;

	# Start the server!
	POE::Component::Server::SimpleHTTP->new(
		'ALIAS'		=>	'HTTPD',
		'ADDRESS'	=>	'192.168.1.1',
		'PORT'		=>	11111,
		'HOSTNAME'	=>	'MySite.com',
		'HANDLERS'	=>	[
			{
				'DIR'		=>	'^/bar/.*',
				'SESSION'	=>	'HTTP_GET',
				'EVENT'		=>	'GOT_BAR',
			},
			{
				'DIR'		=>	'^/$',
				'SESSION'	=>	'HTTP_GET',
				'EVENT'		=>	'GOT_MAIN',
			},
			{
				'DIR'		=>	'.*',
				'SESSION'	=>	'HTTP_GET',
				'EVENT'		=>	'GOT_ERROR',
			},
		],
	) or die 'Unable to create the HTTP Server';

	# Create our own session to receive events from SimpleHTTP
	POE::Session->create(
		inline_states => {
			'_start'	=>	sub {	$_[KERNEL]->alias_set( 'HTTP_GET' );
							$_[KERNEL]->post( 'HTTPD', 'GETHANDLERS', $_[SESSION], 'GOT_HANDLERS' );
						},

			'GOT_BAR'	=>	\&GOT_REQ,
			'GOT_MAIN'	=>	\&GOT_REQ,
			'GOT_ERROR'	=>	\&GOT_ERR,
			'GOT_HANDLERS'	=>	\&GOT_HANDLERS,
		},
	);

	# Start POE!
	POE::Kernel->run();

	sub GOT_HANDLERS {
		# ARG0 = HANDLERS array
		my $handlers = $_[ ARG0 ];

		# Move the first handler to the last one
		push( @$handlers, shift( @$handlers ) );

		# Send it off!
		$_[KERNEL]->post( 'HTTPD', 'SETHANDLERS', $handlers );
	}

	sub GOT_REQ {
		# ARG0 = HTTP::Request object, ARG1 = HTTP::Response object, ARG2 = the DIR that matched
		my( $request, $response, $dirmatch ) = @_[ ARG0 .. ARG2 ];

		# Do our stuff to HTTP::Response
		$response->code( 200 );
		$response->content( 'Some funky HTML here' );

		# We are done!
		$_[KERNEL]->post( 'HTTPD', 'DONE', $response );
	}

	sub GOT_ERR {
		# ARG0 = HTTP::Request object, ARG1 = HTTP::Response object, ARG2 = the DIR that matched
		my( $request, $response, $dirmatch ) = @_[ ARG0 .. ARG2 ];

		# Do our stuff to HTTP::Response
		$response->code( 404 );
		$response->content( "Hi visitor from " . $request->connection->remote_ip . ", Page not found -> '" . $request->uri->path . "'" );

		# We are done!
		$_[KERNEL]->post( 'HTTPD', 'DONE', $response );
	}

=head1 ABSTRACT

	An easy to use HTTP daemon for POE-enabled programs

=head1 CHANGES

=head2 1.04

	Fixed a bug reported by Tim Wood about socket disappearing
	Fixed *another* bug in the Connection object, pesky CaPs! ( Again, reported by Tim Wood )

=head2 1.03

	Added the GETHANDLERS/SETHANDLERS event
	POD updates
	Fixed SimpleHTTP::Connection to get rid of the funky CaPs

=head2 1.02

	Small fix regarding the Got_Error routine for Wheel::ReadWrite

=head2 1.01

	Initial Revision

=head1 DESCRIPTION

This module makes serving up HTTP requests a breeze in POE.

The hardest thing to understand in this module is the HANDLERS. That's it!

The standard way to use this module is to do this:

	use POE;
	use POE::Component::Server::SimpleHTTP;

	POE::Component::Server::SimpleHTTP->new( ... );

	POE::Session->create( ... );

	POE::Kernel->run();

=head2 Starting SimpleHTTP

To start SimpleHTTP, just call it's new method:

	POE::Component::Server::SimpleHTTP->new(
		'ALIAS'		=>	'HTTPD',
		'ADDRESS'	=>	'192.168.1.1',
		'PORT'		=>	11111,
		'HOSTNAME'	=>	'MySite.com',
		'HEADERS'	=>	{},
		'HANDLERS'	=>	[ ],
	);

This method will die on error or return success.

This constructor accepts only 6 options.

=over 4

=item C<ALIAS>

This will set the alias SimpleHTTP uses in the POE Kernel.
This will default to "SimpleHTTP"

=item C<ADDRESS>

This value will be passed to POE::Component::Server::TCP to bind to.

=item C<PORT>

This value will be passed to POE::Component::Server::TCP to bind to.

=item C<HOSTNAME>

This value is for the HTTP::Request's URI to point to.
If this is not supplied, SimpleHTTP will use Sys::Hostname to find it.

=item C<HEADERS>

This should be a hashref, that will become the default headers on all HTTP::Response objects.
You can override this in individual requests by setting it via $request->header( ... )

For more information, consult the L<HTTP::Headers> module.

=item C<HANDLERS>

This is the hardest part of SimpleHTTP :)

You supply an array, with each element being a hash. All the hashes should contain those 3 keys:

DIR	->	The regexp that will be used, more later.

SESSION	->	The session to send the input

EVENT	->	The event to trigger

The DIR key should be a valid regexp. This will be matched against the current request path.
Pseudocode is: if ( $path =~ /$DIR/ )

NOTE: The path is UNIX style, not MSWIN style ( /blah/foo not \blah\foo )

Now, if you supply 100 handlers, how will SimpleHTTP know what to do? Simple! By passing in an array in the first place,
you have already told SimpleHTTP the order of your handlers. They will be tried in order, and if one is not found,
SimpleHTTP will DIE!

This allows some cool things like specifying 3 handlers with DIR of:
'^/foo/.*', '^/$', '.*'

Now, if the request is not in /foo or not root, your 3rd handler will catch it, becoming the "error" handler!

NOTE: You might get weird Session/Events, make sure your handlers are in order, for example: '^/', '^/foo/.*'
The 2nd handler will NEVER get any requests, as the first one will match ( no $ in the regex )

Now, here's what a handler receives:

ARG0 -> HTTP::Request object

ARG1 -> HTTP::Response object

ARG2 -> The exact DIR that matched, so you can see what triggered what

Note: Technically, the HTTP objects are POE::Component::Server::SimpleHTTP::* objects...
There's one added feature in the HTTP::Request object, the connection object.
See the POD for L<POE::Component::Server::SimpleHTTP::Request> and L<POE::Component::Server::SimpleHTTP::Connection> modules.

=back

=head2 Events

SimpleHTTP is so simple, there are only 4 events available.

=over 4

=item C<DONE>

	This event accepts only one argument: the HTTP::Response object we sent off.

	Calling this event implies that this particular request is done, and will proceed to close the socket.

	NOTE: This method automatically sets those 3 headers if they are not already set:
		Date		->	Current date stringified via HTTP::Date
		Content-Type	->	text/html
		Content-Length	->	length( $response->content )

=item C<GETHANDLERS>

	This event accepts 2 arguments: The session + event to send the response to

	This event will send back the current HANDLERS array ( deep-cloned via Storable::dclone )

	The resulting array can be played around to your tastes, then once you are done...

=item C<SETHANDLERS>

	This event accepts only one argument: pointer to HANDLERS array

	BEWARE: if there is an error in the HANDLERS, SimpleHTTP will die!

=item C<SHUTDOWN>

	Calling this event makes SimpleHTTP shut down by closing it's TCP socket.

=back

=head2 SimpleHTTP Notes

This module is very picky about capitalization!

All of the options are uppercase, to avoid confusion.

You can enable debugging mode by doing this:

	sub POE::Component::SimpleHTTP::DEBUG () { 1 }
	use POE::Component::SimpleHTTP;

For those who are pondering about basic-authentication, here's a tiny snippet to put in the Event handler

	# Contributed by Rocco Caputo
	sub Got_Request {
		# ARG0 = HTTP::Request, ARG1 = HTTP::Response
		my( $request, $response ) = @_[ ARG0, ARG1 ];

		# Get the login
		my ( $login, $password ) = $request->authorization_basic();

		# Decide what to do
		if ( ! defined $login or ! defined $password ) {
			# Set the authorization
			$response->header( 'WWW-Authenticate' => 'Basic realm="MyRealm"' );
			$response->code( 401 );
			$response->content( 'FORBIDDEN.' );

			# Send it off!
			$_[KERNEL]->post( 'SimpleHTTP', 'DONE', $response );
		} else {
			# Authenticate the user and move on
		}
	}

=head2 EXPORT

Nothing.

=head1 SEE ALSO

L<POE>

L<POE::Component::Server::HTTP>

L<POE::Filter::HTTPD>

L<HTTP::Request>

L<HTTP::Response>

L<POE::Component::Server::SimpleHTTP::Connection>

L<POE::Component::Server::SimpleHTTP::Request>

L<POE::Component::Server::SimpleHTTP::Response>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
