# Declare our package
package POE::Component::Server::SimpleHTTP;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.05';

# Import what we need from the POE namespace
use POE;
use POE::Wheel::SocketFactory;
use POE::Wheel::ReadWrite;
use POE::Driver::SysRW;
use POE::Filter::HTTPD;

# Other miscellaneous modules we need
use Carp qw( croak );

# HTTP-related modules
use HTTP::Date qw( time2str );

# Our own HTTP modules
use POE::Component::Server::SimpleHTTP::Connection;
use POE::Component::Server::SimpleHTTP::Response;

# Set some constants
BEGIN {
	# Debug fun!
	if ( ! defined &DEBUG ) {
		eval "sub DEBUG () { 0 }";
	}

	# Our own definition of the max retries
	if ( ! defined &MAX_RETRIES ) {
		eval "sub MAX_RETRIES () { 5 }";
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
	if ( exists $opt{'ALIAS'} and defined $opt{'ALIAS'} and length( $opt{'ALIAS'} ) ) {
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
	if ( exists $opt{'PORT'} and defined $opt{'PORT'} and length( $opt{'PORT'} ) ) {
		$PORT = $opt{'PORT'};
		delete $opt{'PORT'};
	} else {
		croak( 'PORT is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Get the ADDRESS
	if ( exists $opt{'ADDRESS'} and defined $opt{'ADDRESS'} and length( $opt{'ADDRESS'} ) ) {
		$ADDRESS = $opt{'ADDRESS'};
		delete $opt{'ADDRESS'};
	} else {
		croak( 'ADDRESS is required to create a new POE::Component::Server::SimpleHTTP instance!' );
	}

	# Get the HOSTNAME
	if ( exists $opt{'HOSTNAME'} and defined $opt{'HOSTNAME'} and length( $opt{'HOSTNAME'} ) ) {
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
	if ( exists $opt{'HEADERS'} and defined $opt{'HEADERS'} ) {
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
	if ( exists $opt{'HANDLERS'} and defined $opt{'HANDLERS'} ) {
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

	# Anything left over is unrecognized
	if ( keys %opt > 0 ) {
		if ( DEBUG ) {
			croak( 'Unrecognized options were present in POE::Component::Server::SimpleHTTP->new -> ' . join( ', ', keys %opt ) );
		}
	}

	# Create a new session for ourself
	POE::Session->create(
		# Our subroutines
		'inline_states'	=>	{
			# Maintenance events
			'_start'	=>	\&StartServer,
			'_stop'		=>	sub {},
			'_child'	=>	sub {},
			'SetupWheel'	=>	\&SetupWheel,

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
			'Got_ServerError'	=>	\&Got_ServerError,

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
			'WHEELS'	=>	{},
			'SOCKETFACTORY'	=>	undef,
			'RETRIES'	=>	0,
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
			if ( UNIVERSAL::isa( $handler->[ $count ]->{'SESSION'}, 'POE::Session' ) ) {
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

# Starts the server!
sub StartServer {
	# Debug stuff
	if ( DEBUG ) {
		warn 'Starting up SimpleHTTP now';
	}

	# Register an alias for ourself
	$_[KERNEL]->alias_set( $_[HEAP]->{'ALIAS'} );

	# Massage the handlers!
	MassageHandlers( $_[HEAP]->{'HANDLERS'} );

	# Setup the wheel
	$_[KERNEL]->yield( 'SetupWheel' );

	# All done!
	return 1;
}

# Sets up the wheel :)
sub SetupWheel {
	# Debug stuff
	if ( DEBUG ) {
		warn 'Creating SocketFactory wheel now';
	}

	# Check if we should set up the wheel
	if ( $_[HEAP]->{'RETRIES'} == MAX_RETRIES ) {
		die 'POE::Component::Server::SimpleHTTP tried ' . MAX_RETRIES . ' times to create a Wheel and is giving up...';
	} else {
		# Increment the retries count
		$_[HEAP]->{'RETRIES'}++;

		# Create our own SocketFactory :)
		$_[HEAP]->{'SOCKETFACTORY'} = POE::Wheel::SocketFactory->new(
			'BindPort'	=>	$_[HEAP]->{'PORT'},
			'BindAddress'	=>	$_[HEAP]->{'ADDRESS'},
			'Reuse'		=>	'yes',
			'SuccessEvent'	=>	'Got_Connection',
			'FailureEvent'	=>	'Got_ServerError',
		);
	}
}

# Stops the server!
sub StopServer {
	# Shutdown the SocketFactory wheel
	delete $_[HEAP]->{'SOCKETFACTORY'};

	# Forcibly close all sockets that are open
	foreach my $conn ( values %{ $_[HEAP]->{'WHEELS'} } ) {
		$conn->[0]->shutdown_input;
		$conn->[0]->shutdown_output;
	}

	# Delete our alias
	$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );

	# Remove all connections
	delete $_[HEAP]->{'WHEELS'};

	# Debug stuff
	if ( DEBUG ) {
		warn 'Successfully stopped SimpleHTTP';
	}

	# Return success
	return 1;
}

# The actual manager of connections
sub Got_Connection {
	# ARG0 = Socket, ARG1 = Remote Address, ARG2 = Remote Port
	my $socket = $_[ ARG0 ];

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
	# 0 = wheel, 1 = Output done?
	$_[HEAP]->{'WHEELS'}->{ $wheel->ID } = [ $wheel, 0 ];

	# Debug stuff
	if ( DEBUG ) {
		warn "Got_Connection completed creation of ReadWrite wheel ( " . $wheel->ID . " )";
	}
}

# Finally got input, set some stuff and send away!
sub Got_Input {
	# ARG0 = HTTP::Request object, ARG1 = Wheel ID
	my( $request, $id ) = @_[ ARG0, ARG1 ];

	# Quick check to see if the socket died already...
	# Initially reported by Tim Wood
	if ( ! defined $_[HEAP]->{'WHEELS'}->{ $id }->[0] or ! defined $_[HEAP]->{'WHEELS'}->{ $id }->[0]->[ POE::Wheel::ReadWrite::HANDLE_INPUT ] ) {
		if ( DEBUG ) {
			warn 'Got a request, but socket died already!';
		}

		# Destroy this wheel!
		delete $_[HEAP]->{'WHEELS'}->{ $id }->[0];
		delete $_[HEAP]->{'WHEELS'}->{ $id };

		# All done!
		return;
	}

	# The HTTP::Response object, the path
	my ( $response, $path );

	# Check if it is HTTP::Request or Response
	# Quoting POE::Filter::HTTPD
	# The HTTPD filter parses the first HTTP 1.0 request from an incoming stream into an
	# HTTP::Request object (if the request is good) or an HTTP::Response object (if the
	# request was malformed).
	if ( ref( $request ) eq 'HTTP::Response' ) {
		# Make the request nothing
		$response = $request;
		$request = undef;

		# Hack it to simulate POE::Component::Server::SimpleHTTP::Response->new( $id, $conn );
		bless( $response, 'POE::Component::Server::SimpleHTTP::Response' );
		$response->{'WHEEL_ID'} = $id;

		# Directly access POE::Wheel::ReadWrite's HANDLE_INPUT -> to get the socket itself
		$response->{'CONNECTION'} = POE::Component::Server::SimpleHTTP::Connection->new( $_[HEAP]->{'WHEELS'}->{ $id }->[0]->[ POE::Wheel::ReadWrite::HANDLE_INPUT ] );

		# Set the path to an empty string
		$path = '';
	} else {
		# Add stuff it needs!
		my $uri = $request->uri;
		$uri->scheme( 'http' );
		$uri->host( $_[HEAP]->{'HOSTNAME'} );
		$uri->port( $_[HEAP]->{'PORT'} );

		# Get the path
		$path = $uri->path();
		if ( ! defined $path or $path eq '' ) {
			# Make it the default handler
			$path = '/';
		}

		# Get the response
		# Directly access POE::Wheel::ReadWrite's HANDLE_INPUT -> to get the socket itself
		$response = POE::Component::Server::SimpleHTTP::Response->new(
			$id,
			POE::Component::Server::SimpleHTTP::Connection->new( $_[HEAP]->{'WHEELS'}->{ $id }->[0]->[ POE::Wheel::ReadWrite::HANDLE_INPUT ] )
		);

		# Stuff the default headers
		$response->header( %{ $_[HEAP]->{'HEADERS'} } );
	}

	# Check if the SimpleHTTP::Connection object croaked ( happens when sockets just disappear )
	if ( ! defined $response->{'CONNECTION'} ) {
		# Destroy this wheel!
		delete $_[HEAP]->{'WHEELS'}->{ $id }->[0];
		delete $_[HEAP]->{'WHEELS'}->{ $id };

		# All done!
		return;
	}

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
	if ( $_[HEAP]->{'WHEELS'}->{ $id }->[1] ) {
		# Shutdown read/write on the wheel
		$_[HEAP]->{'WHEELS'}->{ $id }->[0]->shutdown_input();
		$_[HEAP]->{'WHEELS'}->{ $id }->[0]->shutdown_output();

		# Delete the wheel
		# Tracked down by Paul Visscher
		delete $_[HEAP]->{'WHEELS'}->{ $id }->[0];
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
	# ARG0 = HTTP::Response object
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
	if ( $_[HEAP]->{'WHEELS'}->{ $wheel }->[1] ) {
		# Tried to send twice!
		die 'Tried to send a response to the same connection twice!';
	}

	# Quick check to see if the wheel/socket died already...
	# Initially reported by Tim Wood
	if ( ! defined $_[HEAP]->{'WHEELS'}->{ $wheel }->[0] or ! defined $_[HEAP]->{'WHEELS'}->{ $wheel }->[0]->[ POE::Wheel::ReadWrite::HANDLE_INPUT ] ) {
		if ( DEBUG ) {
			warn 'Tried to send data over a closed/nonexistant socket!';
		}
		return;
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
	$_[HEAP]->{'WHEELS'}->{ $wheel }->[0]->put( $response );

	# Mark this socket done
	$_[HEAP]->{'WHEELS'}->{ $wheel }->[1] = 1;

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

# Got some sort of error from SocketFactory
sub Got_ServerError {
	# ARG0 = operation, ARG1 = error number, ARG2 = error string, ARG3 = wheel ID
	my ( $operation, $errnum, $errstr, $wheel_id ) = @_[ ARG0 .. ARG3 ];

	# Debug stuff
	if ( DEBUG ) {
		warn "SocketFactory Wheel $wheel_id generated $operation error $errnum: $errstr\n";
	}

	# Setup the SocketFactory wheel
	$_[KERNEL]->call( $_[SESSION], 'SetupWheel' );
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
		# For speed, you could use $_[KERNEL]->call( ... )
		$_[KERNEL]->post( 'HTTPD', 'DONE', $response );
	}

	sub GOT_ERR {
		# ARG0 = HTTP::Request object, ARG1 = HTTP::Response object, ARG2 = the DIR that matched
		my( $request, $response, $dirmatch ) = @_[ ARG0 .. ARG2 ];

		# Check for errors
		if ( ! defined $request ) {
			$_[KERNEL]->post( 'HTTPD', 'DONE', $response );
			return;
		}

		# Do our stuff to HTTP::Response
		$response->code( 404 );
		$response->content( "Hi visitor from " . $response->connection->remote_ip . ", Page not found -> '" . $request->uri->path . "'" );

		# We are done!
		# For speed, you could use $_[KERNEL]->call( ... )
		$_[KERNEL]->post( 'HTTPD', 'DONE', $response );
	}

=head1 ABSTRACT

	An easy to use HTTP daemon for POE-enabled programs

=head1 CHANGES

=head2 1.05

	Got rid of POE::Component::Server::TCP and replaced it with POE::Wheel::SocketFactory for speed/efficiency
	As the documentation for POE::Filter::HTTPD says, updated POD to reflect the HTTP::Request/Response issue
	Got rid of SimpleHTTP::Request, due to moving of the Connection object to Response
		->	Found a circular leak by having SimpleHTTP::Connection in SimpleHTTP::Request, to get rid of it, moved it to Response
		->	Realized that sometimes HTTP::Request will be undef, so how would you get the Connection object?
	Internal tweaking to save some memory
	Added the MAX_RETRIES subroutine
	More extensive DEBUG statements
	POD updates
	Paul Visscher tracked down the HTTP::Request object leak, thanks!
	Cleaned up the Makefile.PL
	Benchmarked and found a significant speed difference between post()ing and call()ing the DONE event
		-> The call() method is ~8% faster
		-> However, the chance of connecting sockets timing out is greater...

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

Now, if the request is not in /foo or not root, your 3rd handler will catch it, becoming the "404 not found" handler!

NOTE: You might get weird Session/Events, make sure your handlers are in order, for example: '^/', '^/foo/.*'
The 2nd handler will NEVER get any requests, as the first one will match ( no $ in the regex )

Now, here's what a handler receives:

ARG0 -> HTTP::Request object

ARG1 -> POE::Component::Server::SimpleHTTP::Response object

ARG2 -> The exact DIR that matched, so you can see what triggered what

NOTE: If ARG0 is undef, that means POE::Filter::HTTPD encountered an error parsing the client request, simply modify the HTTP::Response
object and send some sort of generic error. SimpleHTTP will set the path used in matching the DIR regexes to an empty string, so if there
is a "catch-all" DIR regex like '.*', it will catch the errors, and only that one.

=back

=head2 Events

SimpleHTTP is so simple, there are only 4 events available.

=over 4

=item C<DONE>

	This event accepts only one argument: the HTTP::Response object we sent to the handler.

	Calling this event implies that this particular request is done, and will proceed to close the socket.

	NOTE: This method automatically sets those 3 headers if they are not already set:
		Date		->	Current date stringified via HTTP::Date->time2str
		Content-Type	->	text/html
		Content-Length	->	length( $response->content )

	To get greater throughput and response time, do not post() to the DONE event, call() it!
	However, this will force your program to block while servicing web requests...

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

	sub POE::Component::Server::SimpleHTTP::DEBUG () { 1 }
	use POE::Component::Server::SimpleHTTP;

Also, this module will try to keep the SocketFactory wheel alive.
if it dies, it will open it again for a max of 5 retries.

You can override this behavior by doing this:

	sub POE::Component::Server::SimpleHTTP::MAX_RETRIES () { 10 }
	use POE::Component::Server::SimpleHTTP;

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

L<POE::Component::Server::SimpleHTTP::Response>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
