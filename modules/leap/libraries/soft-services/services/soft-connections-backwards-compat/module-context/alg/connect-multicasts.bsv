import FIFO::*;

// connectMulticasts

// One-to-many and Many-to-ones are deffered to the top-level. This actually connects them.


module [CONNECTED_MODULE] connectMulticasts#(Clock clk) ();

    let soft_reset <- getSoftReset();
    
    let send_multis <- getUnmatchedSendMultis();
    let recv_multis <- getUnmatchedRecvMultis();
    
    // It's easier to do this by unique names then by handling sends and recvs separately.
    let send_names = List::map(getSendMultiName, send_multis);
    let recv_names = List::map(getRecvMultiName, recv_multis);
    List#(String) multi_names = uniquify(List::append(send_names, recv_names));
    
    while (!List::isNull(multi_names))
    begin

        let cur_name = List::head(multi_names);
        multi_names = List::tail(multi_names);

        let matching_sends <- findAllMatchingSends(cur_name);
        let matching_recvs <- findAllMatchingRecvs(cur_name);
        let matching_send_multis <- findAllMatchingSendMultis(cur_name);
        let matching_recv_multis <- findAllMatchingRecvMultis(cur_name);

        // The semantics asserts that if there is more than one 1-to-many "foo" 
        // then there should be no 1-to-1s named "foo" in the system, as it would
        // be non-deterministic which it would be connected to. And similarly if
        // there are 2+ many-to-1s named "foo" then there should be no 1-to-1s named
        // foo in the system.

        case (List::length(matching_recv_multis))
            0:
            begin
                case (List::length(matching_send_multis))
                    0:
                    begin
                        // We should never get here unless we messed up our list book-keeping.
                        error("Multicast connection algorithm got into inconsistent state.");
                    end
                    1:
                    begin
                        // The channel is a normal 1-to-many. Connect all recvs (may be zero).
                        connectOneToMany(List::head(matching_send_multis), matching_recvs, clocked_by clk, reset_by soft_reset);
                    end
                    default:
                    begin
                        // This is a bit of a weird case.
                        if (List::length(matching_recvs) != 0)
                        begin
                            messageM("When connecting Multicast " + cur_name + ":");
                            messageM("    Found " + integerToString(List::length(matching_send_multis)) + "One-to-Many Sends");
                            messageM("    Found " + integerToString(List::length(matching_recvs)) + "One-to-One Recvs");
                            error("Inconsistent logical topology. It is ambiguous which One-to-Many the One-to-Ones should be connected to. Perhaps they should be Many-to-One?");
                        end
                        else
                        begin
                            // We got here because many people are talking but no one is listening
                            // Let's count that as a degenerate case of many-to-many.
                            connectManyToMany(cur_name, matching_send_multis, matching_recv_multis, clocked_by clk, reset_by soft_reset);
                        end
                    end
                endcase
            end
            1:
            begin
                case (List::length(matching_send_multis))
                    0:
                    begin
                        // This channel is a normal many-to-one. Connect all sends (may be zero)
                        connectManyToOne(List::head(matching_recv_multis), matching_sends, clocked_by clk, reset_by soft_reset);
                    end
                    default:
                    begin
                       // This channel is many-to-many with only 1 recv.
                       connectManyToMany(cur_name, matching_send_multis, matching_recv_multis, clocked_by clk, reset_by soft_reset);
                    end
                endcase
            end
            default:
            begin
                case (List::length(matching_send_multis))
                    0:
                    begin
                        // This is also a bit of a weird case.
                        if (List::length(matching_sends) != 0)
                        begin
                            messageM("When connecting Multicast " + cur_name + ":");
                            messageM("    Found " + integerToString(List::length(matching_sends)) + "One-to-One Sends");
                            messageM("    Found " + integerToString(List::length(matching_recv_multis)) + "Many-to-One Recvs");
                            error("Inconsistent logical topology. It is ambiguous which Many-to-One the One-to-Ones should be connected to. Perhaps they should be One-to-Many?");
                        end
                        else
                        begin
                            // We got here because many people are listening but no one is talking.
                            // Let's count that as a degenerate case of many-to-many.
                            connectManyToMany(cur_name, matching_send_multis, matching_recv_multis, clocked_by clk, reset_by soft_reset);
                        end
                    end
                    default:
                    begin
                        // This is the normal many-to-many case with many receivers and 1+ sender.
                        connectManyToMany(cur_name, matching_send_multis, matching_recv_multis, clocked_by clk, reset_by soft_reset);
                    end
                endcase
            end
        endcase
    end

endmodule


// connectOneToMany

// Do the actual business of connecting a 1-to-many send to many receivers.

module [CONNECTED_MODULE] connectOneToMany#(LOGICAL_SEND_MULTI_INFO csend, List#(LOGICAL_RECV_INFO) crecvs) ();


    // Registers to scoreboard which receives have received a broadcast transfer.
    List#(Reg#(Bool)) hasReceived = List::nil;
    List#(FIFOF#(PHYSICAL_CONNECTION_DATA)) qs = Nil;
    
    match {.inc_tag, .inc_msg} = csend.outgoing.first();

    for (Integer x = 0; x < List::length(crecvs); x = x + 1)
    begin

        let cur_recv = crecvs[x];

        // Make sure connection types match or consumer is receiving it as void.
        if (csend.logicalType != cur_recv.logicalType && cur_recv.logicalType != "")
        begin

            messageM("Detected send type: " + csend.logicalType);
            messageM("Detected receive type: " + cur_recv.logicalType);
            error("ERROR: data types for broadcast Connection " + csend.logicalName + " do not match.");

        end

        // Make a bit to show whether each receiver has received the broadcast.
        Reg#(Bool) recv <- mkReg(False);
        hasReceived = List::cons(recv, hasReceived);

        // Make a FIFO for each receiver for better throughput.
        let q <- mkUGFIFOF();
        qs = List::cons(q, qs);

        // Try to move messages from the individual FIFO to the receiver.
        rule sendTry (q.notEmpty());

            cur_recv.incoming.try(q.first());

        endrule

        rule sendAck (cur_recv.incoming.success());

            q.deq();

        endrule

    end

    messageM("Connecting 1-to-Many " + csend.logicalName + " to " + integerToString(List::length(crecvs)) + " receives.");

    // This rule transfers an incoming message to all outgoing surrogates.
    // Once all outgoing surrogates have the message, we are done with it.

    rule transferBroadcast (inc_tag matches tagged CONNECTION_BROADCAST &&& csend.outgoing.notEmpty());
    
        // Temporary variable to update list of who's gotten the message.
        List#(Bool) new_recvs = List::replicate(List::length(hasReceived), False);

        for (Integer x = 0; x < List::length(hasReceived); x = x + 1)
        begin
        
            if (!hasReceived[x] && qs[x].notFull())
            begin
                qs[x].enq(inc_msg);
                new_recvs[x] = True;
            end
            else
            begin
                new_recvs[x] = hasReceived[x];
            end
        
        end
        
        if (List::all(\== (True), new_recvs))
        begin
            
            // Everyone's gotten the message. We're done.
            for (Integer x = 0; x < List::length(hasReceived); x = x + 1)
            begin
                hasReceived[x] <= False;
            end
            
            csend.outgoing.deq();

        end
        else
        begin

            // Record who we managed to get the message to.
            for (Integer x = 0; x < List::length(hasReceived); x = x + 1)
            begin
                hasReceived[x] <= new_recvs[x];
            end
            
        end
    
    endrule
    
    rule transferRouted (inc_tag matches tagged CONNECTION_ROUTED .dst &&& 
                         qs[dst].notFull() &&&
                         csend.outgoing.notEmpty());
    
       qs[dst].enq(inc_msg);
       csend.outgoing.deq();
    
    endrule

endmodule


// connectManyToOne

// Connect many sends to a many-to-1 receive.

module [CONNECTED_MODULE] connectManyToOne#(LOGICAL_RECV_MULTI_INFO crecv, List#(LOGICAL_SEND_INFO) csends) ();

    for (Integer x = 0; x < List::length(csends); x = x + 1)
    begin

        let cur_send = csends[x];

        // Make sure connection types match or consumer is receiving it as void.
        if (crecv.logicalType != cur_send.logicalType && crecv.logicalType != "")
        begin

            messageM("Detected send type: " + cur_send.logicalType);
            messageM("Detected receive type: " + crecv.logicalType);
            error("ERROR: data types for Many-to-1 Connection " + cur_send.logicalName + " do not match.");

        end

        rule sendTry (cur_send.outgoing.notEmpty());

            crecv.incoming.try(fromInteger(x), cur_send.outgoing.first());
            
        endrule

        rule sendAck (crecv.incoming.success());
            
            cur_send.outgoing.deq();
            
        endrule
        
    end

    messageM("Connecting Many-to-1 " + crecv.logicalName + " to " + integerToString(List::length(csends)) + " sends.");

endmodule

// connectManyToMany

// Connect many sendMultis to many recvMultis. Note that either list may be 0 (or 1).

module [CONNECTED_MODULE] connectManyToMany#(String name, List#(LOGICAL_SEND_MULTI_INFO) csends, List#(LOGICAL_RECV_MULTI_INFO) crecvs) ();

    List#(List#(FIFOF#(PHYSICAL_CONNECTION_DATA))) qGroups = Nil;
    List#(List#(Reg#(Bool))) recvGroups = Nil;

    for (Integer y = 0; y < List::length(crecvs); y = y + 1)
    begin

        let cur_recv = crecvs[y];
        List#(FIFOF#(PHYSICAL_CONNECTION_DATA)) qs = Nil;
        List#(Reg#(Bool)) recvs = Nil;

        for (Integer x = 0; x < List::length(csends); x = x + 1)
        begin

            let cur_send = csends[x];

            // Make sure connection types match or consumer is receiving it as void.
            if (cur_send.logicalType != cur_recv.logicalType && cur_recv.logicalType != "")
            begin

                messageM("Detected send type: " + cur_send.logicalType);
                messageM("Detected receive type: " + cur_recv.logicalType);
                error("ERROR: data types for multicast connection " + cur_send.logicalName + " do not match.");

            end

            FIFOF#(PHYSICAL_CONNECTION_DATA) q <- mkUGFIFOF();
            qs = List::cons(q, qs);
            
            Reg#(Bool) r <- mkReg(False);
            recvGroups = List::cons(recvs, recvGroups);

            rule sendTry (q.notEmpty());
                cur_recv.incoming.try(fromInteger(x), q.first());
            endrule

            rule sendAck (cur_recv.incoming.success());
                q.deq();
            endrule

       end

       qGroups = List::cons(qs, qGroups);
       recvGroups = List::cons(recvs, recvGroups);

    end

    for (Integer x = 0; x < List::length(csends); x = x + 1)
    begin

        let cur_send = csends[x];
        let qs = qGroups[x];
        let hasReceived = recvGroups[x];
        match {.inc_tag, .inc_msg} = cur_send.outgoing.first();
        
        rule transferBroadcast (inc_tag matches tagged CONNECTION_BROADCAST &&& cur_send.outgoing.notEmpty());

            // Temporary variable to update list of who's gotten the message.
            List#(Bool) new_recvs = List::replicate(List::length(hasReceived), False);

            for (Integer x = 0; x < List::length(hasReceived); x = x + 1)
            begin

                if (!hasReceived[x] && qs[x].notFull())
                begin
                    qs[x].enq(inc_msg);
                    new_recvs[x] = True;
                end
                else
                begin
                    new_recvs[x] = hasReceived[x];
                end

            end

            if (List::all(\== (True), new_recvs))
            begin

                // Everyone's gotten the message. We're done.
                for (Integer x = 0; x < List::length(hasReceived); x = x + 1)
                begin
                    hasReceived[x] <= False;
                end

                cur_send.outgoing.deq();

            end
            else
            begin

                // Record who we managed to get the message to.
                for (Integer x = 0; x < List::length(hasReceived); x = x + 1)
                begin
                    hasReceived[x] <= new_recvs[x];
                end

            end

        endrule

        rule transferRouted (inc_tag matches tagged CONNECTION_ROUTED .dst &&& 
                             qs[dst].notFull() &&&
                             cur_send.outgoing.notEmpty());

           qs[dst].enq(inc_msg);
           cur_send.outgoing.deq();

        endrule

    end

    messageM("Multicast " + name + ": Connecting " + integerToString(List::length(csends)) + "One-to-Many sends to " + integerToString(List::length(crecvs)) + " Many-to-One receives.");

endmodule

// Helper function to make the elements in a list unique.
function List#(a) uniquify(List#(a) l) provisos (Eq#(a));

    function List#(a) uniquify2(List#(a) l2, List#(a) seen) provisos (Eq#(a));
        case (l2) matches
            tagged Nil: return seen;
            default:
            begin
                let x = List::head(l2);
                let xs = List::tail(l2);
                case (List::find( \== (x) , seen)) matches
                    tagged Invalid:  return uniquify2(xs, List::cons(x, seen));
                    tagged Valid .*: return uniquify2(xs, seen);
                endcase
            end
        endcase
    endfunction

    return uniquify2(l, Nil);

endfunction
