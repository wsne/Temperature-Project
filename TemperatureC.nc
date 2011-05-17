/*
 * Copyright (c) 2006 Intel Corporation
 * All rights reserved.
 *
 * This file is distributed under the terms in the attached INTEL-LICENSE     
 * file. If you do not find these files, copies can be found by writing to
 * Intel Research Berkeley, 2150 Shattuck Avenue, Suite 1300, Berkeley, CA, 
 * 94704.  Attention:  Intel License Inquiry.
 */

/**
 * Temperature demo application. See README.txt file in this directory.
 *
 * @author David Gay
 */
#include "Timer.h"
#include "Temperature.h"
#include "printf.h"

module TemperatureC @safe()
{
	uses {
		interface Boot;
		interface SplitControl as RadioControl;
		interface AMSend;
		interface Receive;
		interface Timer<TMilli>;
		interface Read<uint16_t>;
		interface Leds;
		interface PacketAcknowledgements;
	}
}

implementation
{

	void sendReadings();
	message_t sendBuf;
	bool sendBusy;

	/* Current local state - interval, version and accumulated readings */
	temperature_t local;

	uint8_t reading; /* 0 to NREADINGS */

	uint8_t ackTries; /* 0 to NACKTRIES */

	/* When we head an Temperature message, we check it's sample count. If
	   it's ahead of ours, we "jump" forwards (set our count to the received
	   count). However, we must then suppress our next count increment. This
	   is a very simple form of "time" synchronization (for an abstract
	   notion of time). */
	bool suppressCountChange;

	// Use LEDs to report various status issues.
	void report_problem() { 
		printf("REPORT_PROBLEM CALLED \n");
		printfflush();
		call Leds.led0Toggle(); 
	}
	void report_sent() { call Leds.led1Toggle(); }
	void report_received() { call Leds.led2Toggle(); }

	event void Boot.booted() {
		local.interval = DEFAULT_INTERVAL;
		local.id = TOS_NODE_ID;
		if (call RadioControl.start() != SUCCESS)
			report_problem();
	}

	void startTimer() {
		call Timer.startPeriodic(local.interval);
		printf("Timerstarted with %d \n", local.interval);
		printfflush();
		reading = 0;
		ackTries = 0;
		printf("ackTries SET AT START \n");
		printfflush();
	}

	event void RadioControl.startDone(error_t error) {
		startTimer();
	}

	event void RadioControl.stopDone(error_t error) {
	}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
		temperature_t *omsg = payload;

		report_received();

		/* If we receive a newer version, update our interval. 
		   If we hear from a future count, jump ahead but suppress our own change
		 */
		if (omsg->version > local.version && 1==0) 
		{
			//local.version = omsg->version;
			//local.interval = omsg->interval;
			startTimer();
		}
		if (omsg->count > local.count && 1==0)
		{
			local.count = omsg->count;
			suppressCountChange = TRUE;
		}

		return msg;
	}

	/* At each sample period:
	   - if local sample buffer is full, send accumulated samples
	   - read next sample
	 */
	event void Timer.fired() {
		printf("##################\n");
		printf("TimerFired\n");
		printf("##################\n");
		printfflush();
		if (reading == NREADINGS)
		{
			sendReadings();
		}
		if (call Read.read() != SUCCESS)
			report_problem();
	}

	event void AMSend.sendDone(message_t *msg, error_t error) {
		sendBusy = FALSE;
		if(call PacketAcknowledgements.wasAcked(msg)) {
			printf("The package was Acked \n");
			printfflush();
			report_sent();
			ackTries = 0;
			reading = 0;
		} else {
			printf("The package was NOT Acked \n");
			printfflush();
			if (ackTries < NACKTRIES) {
				sendReadings();
			} else if (ackTries == NACKTRIES) {
				printf("ackTries is now == NACKTRIES \n");
				printfflush();
				reading = 0;
				ackTries = 0;
				printf("ackTries RESET NEEDS SLEEPMODE \n");
				printfflush();
			}
		}
	}

	event void Read.readDone(error_t result, uint16_t data) {
		float tempC;
		if (result != SUCCESS)
		{
			data = 0xffff;
			report_problem();
		}
		// conversion
		tempC = ( (-CONVERSION_D1) + (CONVERSION_D2 * data) ) ;
		local.readings[reading++] = tempC;
	}

	void sendReadings() {
		if (!sendBusy && sizeof local <= call AMSend.maxPayloadLength())
		{
			printf("sizeof local <= maxPayload \n");
			printfflush();
			// Don't need to check for null because we've already checked length
			// above
			memcpy(call AMSend.getPayload(&sendBuf, sizeof(local)), &local, sizeof local);
			if (call PacketAcknowledgements.requestAck(&sendBuf) == SUCCESS)
				printf("Success in requestAck\n");
			if (call AMSend.send(41, &sendBuf, sizeof local) == SUCCESS) {
				sendBusy = TRUE;
				ackTries++;
				printf("ackTries = %d \n" , ackTries);
				printfflush();
			}
		}
		if (!sendBusy) {
			report_problem();
		}


		/* Part 2 of cheap "time sync": increment our count if we didn't
		   jump ahead. */
		if (!suppressCountChange)
			local.count++;
		suppressCountChange = FALSE;
	}
}
