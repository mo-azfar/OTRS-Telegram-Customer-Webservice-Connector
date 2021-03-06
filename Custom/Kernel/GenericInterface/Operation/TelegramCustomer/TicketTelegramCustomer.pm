# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --
 
package Kernel::GenericInterface::Operation::TelegramCustomer::TicketTelegramCustomer;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::TelegramCustomer::Common
);

use utf8;
use Encode qw(decode encode);
use Digest::MD5 qw(md5_hex);
use Date::Parse;
use Data::Dumper;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {

            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Token = $ConfigObject->Get('GenericInterface::Operation::TicketTelegramCustomer')->{'Token'};

    if (
        !$Param{Data}->{UserLogin}
        && !$Param{Data}->{CustomerUserLogin}
        && !$Param{Data}->{SessionID}
        )
    {
        return $Self->ReturnError(
            ErrorCode    => 'Telegram.MissingParameter',
            ErrorMessage => "Telegram: UserLogin, CustomerUserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} || $Param{Data}->{CustomerUserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'Telegram.MissingParameter',
                ErrorMessage => "Telegram: Password or SessionID is required!",
            );
        }
    }
	
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'Telegram.AuthFail',
            ErrorMessage => "Telegram: User could not be authenticated!",
        );
    }
    
    #verify the request is from telegram server
    my $AllowedServer = $Self->ValidateTelegramIP(
        REMOTE_ADDR => $ENV{REMOTE_ADDR},
    );
    
    if ( !$AllowedServer ) {
        return $Self->ReturnError (
            ErrorCode    => 'Telegram.IPNotTelegram',
            ErrorMessage => "Telegram: Look like request IP $ENV{REMOTE_ADDR} not from telegram!",
        );
    }
    
    my $GreetText = "Please insert you IC Number (Malaysian) / Passport (Foreigner):";
    my $NoCacheText = "Opps Timeout.Please re-insert you IC Number (Malaysian) / Passport (Foreigner):";
    my $NewTicketText = "Please write your case description:";
    my $CacheType = "TelegramCustomerUser";
    
    #if using text command
    if ( defined $Param{Data}->{message} ) 
    {
        my $Text = $Param{Data}->{message}->{text};
        my $ReplyToText = $Param{Data}->{message}->{reply_to_message}->{text} || 0;
        
        #set cache field for ic/pass
        my $CacheKeyICPass  = "TelegramCUICPass-$Param{Data}->{message}->{chat}->{id}";
            
        #check either this is replied text for IC/Passport input
        if ( $ReplyToText eq $GreetText || $ReplyToText eq $NoCacheText )
        {
            #delete cache if exist
            my $DeleteCache = $CacheObject->Delete(
                Type => $CacheType,       # only [a-zA-Z0-9_] chars usable
                Key  => $CacheKeyICPass,
            );
                
            #create cache for ic/pass
            my $SetCache = $CacheObject->Set(
                Type  => $CacheType,
                Key   => $CacheKeyICPass,
                Value => $Text || '',
                TTL   => 10 * 60, #set cache (means cache for 10 minutes)
            );
        
            my @KeyboardData = (
                [{ 
                    text => "Menu", 
                    callback_data => "/menu",
                }]
                );
            
            #sent message after cache is set
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => "<pre>IC / Passport submitted ($Text). Please click Menu button below to continue</pre>",
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0, 
            );
            
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            }; 
            
        }
        #check either this is replied text for case description input
        elsif ( $ReplyToText eq $NewTicketText )
        {
            ##no need to set cache as this further into process

            #check cache. if not, ask for ic/passport
            my $ICPass = $Self->ValidateCache(
                Type => $CacheType,
                Key  =>  $CacheKeyICPass,
            );
            
            #send telegram if cache empty
            if ( !$ICPass)
            {
                my @KeyboardData = ();
                #sent telegram
                my $Sent = $Self->SentMessage(
                    ChatID => $Param{Data}->{message}->{chat}->{id},
                    MsgID => $Param{Data}->{message}->{message_id},
                    Text => $NoCacheText,
                    Keyboard => \@KeyboardData, #dynamic keyboard
                    Force => \1, 
                    Selective => \1, 
                );
            
                return {
                    Success => 1,
                    Data    => {
                        text => $Sent,
                    },
                };    
                    
            }
            
            my ($CustomerUserID, $Fullname, $CustomerID, $CustomerEmail) = $Self->ValidateTelegramCustomer(
                Customer => $ICPass,
            );
            
            #Create ticket section
            my $NewTicketNumber = $Self->CreateTicket(
                CustomerEmail => $CustomerEmail,
                CustomerID   => $CustomerID,
                CustomerUser => $CustomerUserID,
                RegisteredName => $Fullname,
                Body => $Text,
            );
            
            my @KeyboardData = (
                [{ 
                    text => "Menu", 
                    callback_data => "/menu",
                }]
                );
            
            #sent message after submit case
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => "<pre>Case#$NewTicketNumber received. Thanks</pre>",
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0, 
            );
            
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            }; 
            
        }
        #when new text instead,
        else
        {
            my @KeyboardData = ();
                
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID =>$Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => $GreetText,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \1, 
                Selective => \1, 
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        
    } #end if using text command
    
    
    #if using callback button from SentMessageKeyboard
    elsif ( defined $Param{Data}->{callback_query} ) 
    {
        my $CacheKeyMine   = "TelegramCUmine-$Param{Data}->{callback_query}->{message}->{chat}->{id}";
        my $CacheKeyICPass  = "TelegramCUICPass-$Param{Data}->{callback_query}->{message}->{chat}->{id}";
        
        #check cache. if not, ask for ic/passport
        my $ICPass = $Self->ValidateCache(
            Type => $CacheType,
            Key  =>  $CacheKeyICPass,
        );
        
        #send telegram if cache empty
        if ( !$ICPass)
        {
            my @KeyboardData = ();
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID =>$Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => $NoCacheText,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \1, 
                Selective => \1, 
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };    
                
        }
        
        
        if ($Param{Data}->{callback_query}->{data} eq "/menu") 
        {
            my @KeyboardData = (
            [{ 
				text => "Reset Submitted IC/Password", 
				callback_data => "/reset",
			},
            { 
				text => "Get Profile ID", 
				callback_data => "/profileid",
			}],
            [{ 
				text => "Get WIP Ticket", 
				callback_data => "/mine/wip",
			},
            { 
				text => "Get Resolved Ticket", 
				callback_data => "/mine/closed",
			}],
            [{ 
				text => "Get All Ticket", 
				callback_data => "/mine/all",
			},
            { 
				text => "Submit New Ticket", 
				callback_data => "/new",
			}]
            );
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => "Available command as below for ($ICPass):",
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0,
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        #reset cache
        elsif ($Param{Data}->{callback_query}->{data} eq "/reset")
        {
            #validate false cache, so error.
            my $ICPass = $Self->ValidateCache(
                Type => $CacheType,
                Key  =>  'NA',
            );
            
            #send telegram if cache empty
            if ( !$ICPass)
            {
                my @KeyboardData = ();
                #sent telegram
                my $Sent = $Self->SentMessage(
                    ChatID =>$Param{Data}->{callback_query}->{message}->{chat}->{id},
                    MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                    Text => $NoCacheText,
                    Keyboard => \@KeyboardData, #dynamic keyboard
                    Force => \1, 
                    Selective => \1, 
                );
            
                return {
                    Success => 1,
                    Data    => {
                        text => $Sent,
                    },
                };    
                    
            }
            
         
        }
        
        #check profile
        elsif ($Param{Data}->{callback_query}->{data} eq "/profileid")
        {
         
            my ($CustomerUserID, $Fullname, $CustomerID, $CustomerEmail) = $Self->ValidateTelegramCustomer(
                Customer => $ICPass,
            );
            
            my $Text;
            if ($CustomerUserID eq "N/A")
            {
                $Text = "<pre>Profile for keyword $ICPass not found or not valid</pre>";
            }
            else
            {
                $Text = "<pre>Found It!\nIC / Passport: $ICPass\nRegistered ID: $CustomerUserID\nRegistered Name: $Fullname</pre>";
            }
            
            my @KeyboardData = (
            [{ 
				text => "Menu", 
				callback_data => "/menu",
			}],
            );
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => $Text,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0,
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        #check ticket
        elsif ($Param{Data}->{callback_query}->{data} eq "/mine/wip" || $Param{Data}->{callback_query}->{data} eq "/mine/closed" || $Param{Data}->{callback_query}->{data} eq "/mine/all")
        {
            
            #delete cache if exist (for mine selected button)
            $CacheObject->Delete(
                Type => $CacheType,       # only [a-zA-Z0-9_] chars usable
                Key  => $CacheKeyMine,
            );
            
            #create cache for selected mine button
            $CacheObject->Set(
                Type  => $CacheType,
                Key   => $CacheKeyMine,
                Value => $Param{Data}->{callback_query}->{data} || '',
                TTL   => 3 * 60, #set cache (means cache for 3 minutes)
            );
            
            my @PossibleStateType = ();
            if ($Param{Data}->{callback_query}->{data} eq "/mine/wip")
            {
                @PossibleStateType = ('new', 'open', 'pending reminder', 'pending auto'); 
            }
            elsif ($Param{Data}->{callback_query}->{data} eq "/mine/closed")
            {
                @PossibleStateType = ('closed'); 
            }
            elsif ($Param{Data}->{callback_query}->{data} eq "/mine/all")
            {
                @PossibleStateType = ('new', 'open', 'pending reminder', 'pending auto', 'closed'); 
            }
            
                        
            my ($CustomerUserID, $Fullname, $CustomerID, $CustomerEmail) = $Self->ValidateTelegramCustomer(
                Customer => $Param{Data}->{callback_query}->{message}->{chat}->{id},
            );
            
            my $FilterBy;
            if ($CustomerUserID eq "N/A")
            {
                $FilterBy = "Ticket";
            }
            else
            {
                $FilterBy = "CustomerUser";
            }
            
            
            #check my ticket depending on state type
            my ($CheckMyTicket, @KeyboardTicketData) = $Self->CheckMyTicket(
                SearchValue => $ICPass,
                Condition => \@PossibleStateType,
                FilterBy => $FilterBy,
                Customer => $CustomerUserID,
            );
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text =>  $CheckMyTicket,
                Keyboard => \@KeyboardTicketData, #dynamic keyboard list based of number of ticket (ticket id, ticket number) found in api above.
                Force => \0, 
                Selective => \0,
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        #check ticket details
        elsif ($Param{Data}->{callback_query}->{data} =~ "^/get/")
        {
        
            my @gettid = split '/', $Param{Data}->{callback_query}->{data};
            my $tid = $gettid[2];
            
            #get ticket details
            my $getTicket = $Self->GetTicket(
                TicketID => $tid,
            );
            
            #get back previous mine selection via cache or set default to wip if empty
            my $PrevMine = $CacheObject->Get(
                Type => $CacheType,
                Key  => $CacheKeyMine,
            ) || '/mine/wip';
    
            my @KeyboardData = (
            [{ 
				text => "Menu", 
				callback_data => "/menu",
			},
            { 
				text => "Go back To List", 
				callback_data => "$PrevMine",
			}],
            );
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => $getTicket,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0,
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        #new ticket
        elsif ($Param{Data}->{callback_query}->{data} eq "/new")
        {
         
            my ($CustomerUserID, $Fullname, $CustomerID, $CustomerEmail) = $Self->ValidateTelegramCustomer(
                Customer => $ICPass,
            );
            
            if ($CustomerUserID eq "N/A")
            {
                
                my @KeyboardData = (
                [{ 
                    text => "Menu", 
                    callback_data => "/menu",
                }],
                );
            
                #sent telegram
                my $Sent = $Self->SentMessage(
                    ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                    MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                    Text => "Opss..only registered and valid profile in OTRS allowed to submit a new ticket",
                    Keyboard => \@KeyboardData, #dynamic keyboard
                    Force => \0, 
                    Selective => \0,
                );
        
                return {
                    Success => 1,
                    Data    => {
                        text => $Sent,
                    },
                };
             
            }
            else
            {
                
                my @KeyboardData = ();
                
                #sent telegram
                my $Sent1 = $Self->SentMessage(
                    ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                    MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                    Text => "<pre>Registered ID: $CustomerUserID\nRegistered Name: $Fullname</pre>",
                    Keyboard => \@KeyboardData, #dynamic keyboard
                    Force => \0, 
                    Selective => \0,
                );
                
                #sent telegram
                my $Sent2 = $Self->SentMessage(
                    ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                    MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                    Text => "$NewTicketText",
                    Keyboard => \@KeyboardData, #dynamic keyboard
                    Force => \1, 
                    Selective => \1,
                );
        
                return {
                    Success => 1,
                    Data    => {
                        text => "$Sent1 $Sent2",
                    },
                };
             
            }
            
        }
        
        else ##another button
        {
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text =>  "Button clicked!!",
                Force => \0, 
                Selective => \0, 
            );
        
            return {
                    Success => 1,
                    Data    => {
                        text => "$Sent",
                    },
            };
        }    
    } #end if using callback button from SentMessageKeyboard
    
}

1;
