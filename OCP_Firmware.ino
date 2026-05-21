#include <SPI.h>

#define PIN_SEN     2   // Serial Enable
#define SPICLK      3  // Serial Clock
#define SPIMOSI     4   // Serial Data (MOSI)
#define SPIMISO     -1   // Không dùng
// Cấu hình SPI: 1MHz, MSB First, SPI Mode 0
// PE64906 hoạt động tốt nhất ở Mode 0
SPISettings dtcSettings(100000, MSBFIRST, SPI_MODE0);

void setCapacitance(uint8_t state) {
  // state từ 0 đến 31 (5-bit)
  // Register map: [0][0][STB][d4][d3][d2][d1][d0]
  // STB = 0 là hoạt động, STB = 1 là thấp công suất (standby)
  if (state > 31) state = 31;

   SPI.beginTransaction(dtcSettings);
  digitalWrite(PIN_SEN, LOW);
  delay(1);
  digitalWrite(PIN_SEN, HIGH);
  delay(1);
 
  delay(1);
  // Gửi dữ liệu (DTC sẽ nhận 8 bit, lấy 5 bit cuối làm giá trị điện dung)
  Serial.print("Truyen");
  Serial.println(state);
  SPI.transfer(state);
  Serial.println(" xong.");
  delay(1);
  digitalWrite(PIN_SEN, LOW);
  // Kéo SEN lên cao để "chốt" (latch) dữ liệu vào tụ điện

  SPI.endTransaction();
}

void setup() {
  Serial.begin(115200);
  Serial.println("DTC PE64906 - Arduino Uno Control");

  // Thiết lập chân SEN
  pinMode(PIN_SEN, OUTPUT);
  SPI.begin(SPICLK, SPIMISO, SPIMOSI, -1);
  digitalWrite(PIN_SEN, HIGH);

  Serial.println("Da khoi tao xong!");
  delay(4000);
  //  setCapacitance(1);
}

void loop() {
  
  delay(2000);
  for (int i = 0; i < 21; i++) {
    Serial.print("Dang dat gia tri: ");
    Serial.println(i);
    
    setCapacitance(i);
    
    delay(5000); // Chờ 1 giây để quan sát
  }
}