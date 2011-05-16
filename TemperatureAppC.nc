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
 * Temperature demo application. Uses the demo sensor - change the
 * new DemoSensorC() instantiation if you want something else.
 *
 * See README.txt file in this directory for usage instructions.
 *
 * @author David Gay
 */
configuration TemperatureAppC { }
implementation
{
  components TemperatureC, MainC, ActiveMessageC, LedsC,
    new TimerMilliC(), new DemoSensorC() as Sensor, 
    new AMSenderC(AM_OSCILLOSCOPE), new AMReceiverC(AM_OSCILLOSCOPE);

  TemperatureC.Boot -> MainC;
  TemperatureC.RadioControl -> ActiveMessageC;
  TemperatureC.AMSend -> AMSenderC;
  TemperatureC.Receive -> AMReceiverC;
  TemperatureC.Timer -> TimerMilliC;
  TemperatureC.Read -> Sensor;
  TemperatureC.Leds -> LedsC;

  
}
