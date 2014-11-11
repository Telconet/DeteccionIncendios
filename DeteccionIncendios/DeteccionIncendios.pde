

/*  
 *  ------ Waspmote Pro Code Example -------- 
 *  
 *  Explanation: This is the basic Code for Waspmote Pro
 *  
 *  Copyright (C) 2013 Libelium Comunicaciones Distribuidas S.L. 
 *  http://www.libelium.com 
 *  
 *  This program is free software: you can redistribute it and/or modify  
 *  it under the terms of the GNU General Public License as published by  
 *  the Free Software Foundation, either version 3 of the License, or  
 *  (at your option) any later version.  
 *   
 *  This program is distributed in the hope that it will be useful,  
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of  
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the  
 *  GNU General Public License for more details.  
 *   
 *  You should have received a copy of the GNU General Public License  
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.  
 */

// Put your libraries here (#include ...)

#include <WaspSensorGas_v20.h>
#include <WaspXBeeDM.h>
#include <WaspFrame.h>
#include <WaspFrameConstants.h>
#include <stdint.h>
#include <string.h>

//Constantes
#define GANANCIA_SENSOR_CO2  8    //usualmente entre 7 y 10...
#define GANANCIA_SENSOR_CO 1      // GAIN of the sensor stage
#define RESISTENCIA_CO 100 
#define TIEMPO_ESTABILIZACION_SENSOR_CO2    50000
#define TIEMPO_SLEEP 600000       //10 minutos de sleep....
#define TIEMPO_ENCENDIDO_TARJETA_GASES 100
#define NUMERO_REINTENTOS_XBEE 10

#define COORDINADOR


//Variables globales de informacion
float CO2v = 0.0f;
float COv = 0.0f;
float temperatura = 0.0f;
float humedad = 0.0f;          //%HR

//Variables de comunicacion
WaspXBeeDM moduloXBeeDM;
packetXBee *paquete = NULL;
char informacion_recibida[MAX_DATA] = { 0 };

//MAC del Meshlium...
char meshlium_mac[17] = {  0  };
char waspmote_id[17] = {0};

//Llave encriptcion
char *LLAVE = "@df345GF";

//Parametros sync sleep.
uint8_t asleep[3] = { 0x00, 0xEA, 0x60 };
uint8_t wakeup[3] = { 0x00, 0x17, 0x70 };

void setup() {
  // put your setup code here, to run once:

  // Init USB port
  USB.ON();
  USB.println(F("DM_02 example"));

  //RTC
  RTC.ON();

  //Configuramos la ganancia del sensor CO2
  SensorGasv20.configureSensor(SENS_CO2, GANANCIA_SENSOR_CO2);     

  //Configuramos sensor de CO --> SENS_SOCKET3CO or SENS_SOCKET4CO
  SensorGasv20.configureSensor(SENS_SOCKET4CO, GANANCIA_SENSOR_CO, RESISTENCIA_CO);

  //Configuramos los parametros del XBee DigiMesh.
  xbeeDM.ON();

  delay(1000);
  xbeeDM.flush();

  //Canal
  xbeeDM.setChannel(0x15);    //canal 21...

  //ID red...
  uint8_t PAN_ID[2] = { 0x5f , 0x7b   };
  xbeeDM.setPAN(PAN_ID);

  //Configurar encriptacion
  xbeeDM.setEncryptionMode(1);
  xbeeDM.setLinkKey(LLAVE);
  
  //Configuracion sleep
  //Usamos sleep cíclico sincronizado
  //Los modulos en modo acíclico NO pueden ser
  //usados para comunicación dentro del mesh
  
#ifdef COORDINADOR
  USB.println(F("Configurando nodo coordinador"));
  xbeeDM.setSleepTime(asleep);
  
   if( xbeeDM.error_AT == 0 ) 
  {
    USB.println(F("ST parameter set ok"));
  }
  else 
  {
    USB.println(F("error setting ST parameter")); 
  }
  
  xbeeDM.setAwakeTime(wakeup);
  
  if( xbeeDM.error_AT == 0 ) 
  {
    USB.println(F("SP parameter set ok"));
  }
  else 
  {
    USB.println(F("error setting SP parameter")); 
  }
  
  xbeeDM.setSleepMode(7);            //
  xbeeDM.setSleepOptions(0x01);      //Preferred sleep coordinator...
#else
  USB.println(F("Configurando nodo esclavo"));
  xbeeDM.setSleepMode(8);            //Dormira cuando coordinador envie paquete...
  xbeeDM.setSleepOptions(0x02);      //Nunca coordinador
  
#endif

  //Escribir valores al modulo XBee
  xbeeDM.writeValues();
  
  //Obtener info del equipo...
   //Revisar EEPROM... direcciones de 1024 a 4095 están disponibles...
  //Meshlium MAC -> 16 bytes + 2 bytes (si es valido o no);    1024 a 1041...
  //I.e. OKabcdef01234567890  --> Meshlium MAC ok
  //     NOxxxxxxxxxxxxxxxxx  --> Meshlium MAC not ok
  int meslium_mac_eeprom_start_add = 1024;

  int i = 0;
  int tmp = 0;

  for(i = 0; i < 18; i++){
    tmp = Utils.readEEPROM(meslium_mac_eeprom_start_add + i);

    //Si direccion es invalida, tenemos que obtenerla...
    if(i == 0 && tmp != 'O'){
      break;
    }
    else if(i == 1 && tmp != 'K'){
      break;
    }
    else if(i >= 2){
      meshlium_mac[i - 2] = (char)tmp;
    }
  }
  
  
  //Si no tenemos el meshlium mac, esperamos por el...
  if(i < 2){
    
    while(true){
      if(recbirDatosRequeridos("MM", true, meslium_mac_eeprom_start_add) == 0){
        break;
      }
    }    
  }


  //Waspmote ID... de direcction 1041 + 18 - 1 = 1058
  //OKxxxxxxxxxxxx
  //NOxxxxxxxxxxxx
  int wm_id_eeprom_start_add = 1041;

  i = 0;
  tmp = 0;

  for(i = 0; i < 18; i++){
    tmp = Utils.readEEPROM(wm_id_eeprom_start_add + i);

    //Si direccion es invalida, tenemos que obtenerla...
    if(i == 0 && tmp != 'O'){
      break;
    }
    else if(i == 1 && tmp != 'K'){
      break;
    }
    else if(i >= 2){
      waspmote_id[i - 2] = (char)tmp;
    }
  }

  //si no tenemos el id, esperamos por él
  if(i < 2){
    while(true){
      if(recbirDatosRequeridos("ID", true, wm_id_eeprom_start_add) == 0){
        break;
      }
    }   
  }
}


void loop() {

  //Empezamos a medir
  //sleep... sync!!
  enableInterrupts(XBEE_INT);
  PWR.sleep(UART1_OFF);

    
    
  if(intFlag & XBEE_INT){
    USB.println("XBee nos desperto");
    intFlag &= ~(XBEE_INT);
  }


  //De aqui dormirenos despues de wakeup segundos
  //Encendemos tarjeta de sensores...
  SensorGasv20.ON();
  delay(TIEMPO_ENCENDIDO_TARJETA_GASES);

  SensorGasv20.setSensorMode(SENS_ON, SENS_CO2);
  delay(TIEMPO_ESTABILIZACION_SENSOR_CO2); 

  //Medimos CO2 --> nos da voltaje. Usar grafico para converir a ppm...
  CO2v = SensorGasv20.readValue(SENS_CO2);      //Nos da el voltaje del sensor


  //Medir CO
  COv = SensorGasv20.readValue(SENS_SOCKET4CO);
  COv = SensorGasv20.calculateResistance(SENS_SOCKET4CO, COv, GANANCIA_SENSOR_CO, RESISTENCIA_CO);    //Aqui obtenemos la resistencia. Usar grafico para convertir a ppm

  //Medir temperatura y humedad
  humedad = SensorGasv20.readValue(SENS_HUMIDITY);
  temperatura = SensorGasv20.readValue(SENS_TEMPERATURE);

  //Convertimos el voltaje a PPM??

  //Apagamos tarjeta de sensores...
  SensorGasv20.OFF();

  //Creamos el paquete con la información de los sensors...
  frame.createFrame(ASCII, waspmote_id); 
  
  frame.setID(waspmote_id);

  frame.addSensor(SENSOR_CO2, (float) CO2v);
  frame.addSensor(SENSOR_CO2, (float) CO2v);
  frame.addSensor(SENSOR_HUMA, (float) humedad);
  frame.addSensor(SENSOR_TCA, (float) temperatura);
  frame.addSensor(SENSOR_BAT, (uint8_t) PWR.getBatteryLevel());

  //Creamos el paquete 
  paquete = (packetXBee*) calloc(1, sizeof(packetXBee));
  paquete->mode = UNICAST;

  //Ponemos el frame en el paquete
  xbeeDM.setDestinationParams(paquete, meshlium_mac, frame.buffer, frame.length);

  //Enviamos...
  xbeeDM.sendXBee(paquete);

  uint8_t reintentos = 0;

  while(xbeeDM.error_TX != 0){

    if(reintentos > NUMERO_REINTENTOS_XBEE){
      break;
    }

    reintentos++;
    delay(1000);
    xbeeDM.sendXBee(paquete);
  }

  //
  free(paquete);
  paquete = NULL;
  
  delay(1000);
  
}


//Funcion que recibe datos del modulo Xbee
//datoRequerido es ID (waspmoteid id), MM (meshlium mac)
//almacenar indica si debemos escribir datos en la EEPROM
//staradd indica direccion de EEPROM 
int recbirDatosRequeridos(const char *datoRequerido, bool almacenar, int startadd){
  
  int len = 0;
  int tipo = 0;
  
  //Que tipo de datos esperamos y su longitud
  if(strstr(datoRequerido, "ID")){
    len = 18;
    tipo = 1;
  }
  else if(strstr(datoRequerido, "MM")){
    len = 18;
    tipo = 2;
  }
  
  //Si recibimos info...
  if(xbeeDM.available() > 0){

    xbeeDM.treatData();

    // check RX flag after 'treatData'
    if(!xbeeDM.error_RX){

      //Copiamos el string...
      memset(informacion_recibida, 0, MAX_DATA);

      for(int i=0 ; i < xbeeDM.packet_finished[xbeeDM.pos-1]->data_length ; i++)          
      { 

        informacion_recibida[i] = (char) xbeeDM.packet_finished[xbeeDM.pos-1]->data[i];

        // Print data payload
        //USB.print(xbeeDM.packet_finished[xbeeDM.pos-1]->data[i], BYTE);          
      }

      //Verificar si es la info que necesitamos
      if(strstr(informacion_recibida, datoRequerido) != NULL){

        int j = 0;
        for(j = 0; j < len; j++){

          if(j == 0){
            if(almacenar){
              Utils.writeEEPROM(startadd + j, 'O');
            }
          }
          else if(j == 1){
            if(almacenar){
              Utils.writeEEPROM(startadd + j, 'K');
            }
          }
          else{
            
            if(tipo == 1){
               meshlium_mac[j - 2] = informacion_recibida[j - 2];
            }
            if(tipo == 2){
              waspmote_id[j - 2] = informacion_recibida[j - 2];
            }
            if(almacenar){
              Utils.writeEEPROM(startadd + j, informacion_recibida[j - 2]);
            }
          }
        }
        
        //
        free(xbeeDM.packet_finished[xbeeDM.pos-1]); 
  
        //free pointer
        xbeeDM.packet_finished[xbeeDM.pos-1]= NULL; 
  
        //Decrement the received packet counter
        xbeeDM.pos--; 
        
        return 0;
      }
      else{
        free(xbeeDM.packet_finished[xbeeDM.pos-1]); 
  
        //free pointer
        xbeeDM.packet_finished[xbeeDM.pos-1]= NULL; 
  
        //Decrement the received packet counter
        xbeeDM.pos--; 
        
        return -1;
      }
    }
  }
  
  return -1;
}



