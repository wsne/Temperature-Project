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
		interface PacketLink;
	}
}
implementation
{
	message_t sendBuf;
	bool sendBusy;

	/* Current local state - interval, version and accumulated readings */
	temperature_t local;

	uint8_t reading; /* 0 to NREADINGS */
	uint16_t average; /* 0 to NAVERAGES */
	uint8_t averages; /* 0 to NAVERAGES */

	/* When we head an Temperature message, we check it's sample count. If
	   it's ahead of ours, we "jump" forwards (set our count to the received
	   count). However, we must then suppress our next count increment. This
	   is a very simple form of "time" synchronization (for an abstract
	   notion of time). */
	bool suppressCountChange;

	// Use LEDs to report various status issues.
	void report_problem() { call Leds.led0On(); }
	void report_sent() { call Leds.led0Off(); call Leds.led1Toggle(); }
	void report_received() {}

	event void Boot.booted() {
		local.interval = DEFAULT_INTERVAL;
		local.id = TOS_NODE_ID;
		average = 0;
		if (call RadioControl.start() != SUCCESS)
			report_problem();
	}

	void startTimer() {
		call Timer.startPeriodic(local.interval);
		reading = 0;
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
		if (omsg->version > local.version)
		{
			local.version = omsg->version;
			local.interval = omsg->interval;
			startTimer();
		}
		if (omsg->count > local.count)
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
		if (averages == NAVERAGES)
		{
			if (!sendBusy && sizeof local <= call AMSend.maxPayloadLength())
			{
				// Don't need to check for null because we've already checked length
				// above
				memcpy(call AMSend.getPayload(&sendBuf, sizeof(local)), &local, sizeof local);

				call PacketLink.setRetries(&sendBuf, NACKTRIES);
				call PacketLink.setRetryDelay(&sendBuf, RETRYDELAY);

				if (call AMSend.send(BASESTATION, &sendBuf, sizeof local) == SUCCESS)
					sendBusy = TRUE;
			}
			if (!sendBusy)
				report_problem();

			reading = 0;
			averages = 0;
			/* Part 2 of cheap "time sync": increment our count if we didn't
			   jump ahead. */
			if (!suppressCountChange)
				local.count++;
			suppressCountChange = FALSE;
		}
		if (call Read.read() != SUCCESS)
			report_problem();
	}

	event void AMSend.sendDone(message_t* msg, error_t error) {
		if (call PacketLink.wasDelivered(msg))
			report_sent();
		else
			report_problem();

		sendBusy = FALSE;
	}

	event void Read.readDone(error_t result, uint16_t data) {
		float tempC = 0;
		if (result != SUCCESS)
		{
			data = 0xffff;
			report_problem();
		}
		// conversion
		tempC = ( (-CONVERSION_D1) + (CONVERSION_D2 * data) ) ;
		reading++;
		average = average + (tempC / NREADINGS);
		if (reading == NREADINGS) {
			local.averages[averages++] = average;
			average = 0;
			reading = 0;
		}
	}
}
