package hfpanel;

use strict;
use warnings;

use QtCore4;
use QtGui4;
use QtCore4::isa qw( Qt::Dialog);
use QtCore4::slots
    startButton_clicked => [],
    buttonOk_clicked => [],
    sendSwitchMessage => ['int', 'int'],
    switch0_valueChanged => ['int'],
    switch1_valueChanged => ['int'],
    switch2_valueChanged => ['int'],
    switch3_valueChanged => ['int'],
    switch4_released => [],
    switch4_pressed => [],
    switch5_released => [],
    switch5_pressed => [],
    switch6_released => [],
    switch6_pressed => [],
    switch7_released => [],
    switch7_pressed => [],
    switch8_released => [],
    switch8_pressed => [];


use IO::Select;
my @ledArray;
my @switchArray;
my @switchCache;
my $scanning;

sub ui() 
{
    return this->{ui};
}

sub NEW 
{
    my ( $class, $parent ) = @_;
    $class->SUPER::NEW($parent);
    this->{ui} = Ui_Hfpanel->setupUi(this);
    init();
}


sub init
{

    $scanning = 0;
    
    $ledArray[0] = ui()->led0_off();
    $ledArray[1] = ui()->led1_off();
    $ledArray[2] = ui()->led2_off();
    $ledArray[3] = ui()->led3_off();
    $ledArray[4] = ui()->led4_off();
    $ledArray[5] = ui()->led5_off();
    $ledArray[6] = ui()->led6_off();
    $ledArray[7] = ui()->led7_off();

    $switchArray[0] = ui()->switch0();
    $switchArray[1] = ui()->switch1();
    $switchArray[2] = ui()->switch2();
    $switchArray[3] = ui()->switch3();
    $switchArray[4] = ui()->switch4();
    $switchArray[5] = ui()->switch5();
    $switchArray[6] = ui()->switch6();
    $switchArray[7] = ui()->switch7();
    $switchArray[8] = ui()->switch8();

    my $string_of_32_zeroes = "00000000000000000000000000000000";
    @switchCache = split(//, $string_of_32_zeroes);

    # disable all input controls except Start button
    ui->groupSwitches()->setEnabled(0);
    ui()->groupButtons()->setEnabled(0);
    ui()->groupLEDs()->setEnabled(0);

    $| = 1;

}

sub startButton_clicked
{

    my $timeout = 0.001;
    
    # sanity check
    if ($scanning eq 1)
    {
        die "invalid state: 1\n";
    }
        
    # enable dialog controls... do we need an atomic
    # condition variable here?
    $scanning = 1;

    ui()->startButton()->setEnabled(0);
    ui()->groupSwitches()->setEnabled(1);
    ui()->groupButtons()->setEnabled(1);
    ui()->groupLEDs()->setEnabled(1);
        
    # start scanning inputs
    my $sel = new IO::Select;
    $sel->add(\*STDIN);

    # flush all junk from STDIN
    # while ($sel->can_read($timeout))
    # {
    #    my $junk;
    #    read(STDIN, $junk, 1);
    # }
        
    # enter scan loop
    while ($scanning eq 1)
    {
        # scan for events
        if ($sel->can_read($timeout))
        {
            # incoming!
            my $data;
            read(STDIN, $data, 32);

            # update LED state: be careful about endian-ness!
            for (my $led = 0; $led < 8; $led = $led + 1)
            {
                # in our dialog box, the off-state LED is on top,
                # so to switch "on" the LED, we need to hide the
                # off-state pixmap, and to switch it "off", we need
                # to reveal the off-state pixmap
                if (substr($data, $led, 1) eq '0')
                {
                    $ledArray[$led]->show();
                    print "inside show for led = $led\n";
                }
                else
                {
                    print "inside hide for led = $led\n";
                    $ledArray[$led]->hide();
                }
            }
        }
            
        # ugh, this is really ugly: manually ask
        # application to process events so that event
        # loop is alive. It is theoretically possible
        # for more than one instance of this loop to
        # be running simultaneously, but it is extremely
        # unlikely, and even if this happens, there
        # aren't any critical race conditions (I think).
          
        qApp->processEvents();
    }
        
    # we've come out of the scan loop, perform cleanup

}

sub buttonOk_clicked
{

    # check if scan loop is running
    if ($scanning eq 0)
    {
        # nothing to do, simply exit
    }
    else
    {
        # set flag to come out of scan loop
        $scanning = 0;
    }

    # note: accept() will be called after this method ends,
    # which will cause the app to terminate

}

sub sendSwitchMessage
{

    # construct string and print it out
    $switchCache[$_[0]] = $_[1];

    print STDOUT @switchCache;

    #print STDOUT "$_[0] $_[1]\n";

}

sub switch0_valueChanged
{

    sendSwitchMessage(0, $_[0]);

}

sub switch1_valueChanged
{

    sendSwitchMessage(1, $_[0]);

}

sub switch2_valueChanged
{

    sendSwitchMessage(2, $_[0]);

}

sub switch3_valueChanged
{

    sendSwitchMessage(3, $_[0]);

}

sub switch4_released
{

    sendSwitchMessage(4, 0);

}

sub switch4_pressed
{

    sendSwitchMessage(4, 1);

}

sub switch5_released
{

    sendSwitchMessage(5, 0);

}

sub switch5_pressed
{

    sendSwitchMessage(5, 1);

}

sub switch6_released
{

    sendSwitchMessage(6, 0);

}

sub switch6_pressed
{

    sendSwitchMessage(6, 1);

}

sub switch7_released
{

    sendSwitchMessage(7, 0);

}

sub switch7_pressed
{

    sendSwitchMessage(7, 1);

}

sub switch8_released
{

    sendSwitchMessage(8, 0);

}

sub switch8_pressed
{

    sendSwitchMessage(8, 1);

}



package main;
#
# Create main window
#

use hfpanel;

our $app = Qt::Application(\@ARGV);
my $w = hfpanel();

$w->show();
exit $app->exec();



