import BeerTempFeatures
import Dependencies
import Foundation

#if targetEnvironment(simulator)
  extension BluetoothClient {
    /// A mock BluetoothClient that simulates a sensor with temperature
    /// rising from ~20°C toward ~70°C using a saturating exponential curve.
    /// Updates every second via the discoveredSensors stream.
    static let simulator: BluetoothClient = {
      let state = SimulatorBLEState()
      return BluetoothClient(
        startScanning: {
          await state.start()
        },
        stopScanning: {
          await state.stop()
        },
        discoveredSensors: {
          AsyncStream { continuation in
            Task {
              await state.emitDiscoveries(continuation: continuation)
            }
          }
        },
        connect: { _ in },
        disconnect: { _ in },
        temperatureUpdates: { _ in .finished },
        targetValueProgressUpdates: { _ in .finished },
        setTargetValue: { _, value in
          await state.setTarget(value)
          return value
        },
        readTargetValue: { _ in
          await state.getTarget()
        }
      )
    }()
  }

  private actor SimulatorBLEState {
    let sensorID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private var isRunning = false
    private var startTime = Date()
    private var target: Double? = nil

    func start() {
      isRunning = true
      startTime = Date()
    }

    func stop() {
      isRunning = false
    }

    func setTarget(_ value: Double?) {
      target = value
    }

    func getTarget() -> Double? {
      target
    }

    func emitDiscoveries(continuation: AsyncStream<DiscoveredSensor>.Continuation) async {
        while isRunning {
          let elapsed = Date().timeIntervalSince(startTime)
          let temp: Double
          // Phase 1: Rise from 20°C toward 80°C on a saturating exponential
          // T = 20 + 60 * (1 - e^(-0.05*t)), reaches ~60°C around t≈60s
          let rising = 20.0 + 60.0 * (1.0 - exp(-0.05 * elapsed))
          if rising < 59.5 {
            temp = rising
          } else {
            // Phase 2: Heater off — exponential decay from 60°C toward 20°C
            let tSwitch = -log(1.0 - 39.5 / 60.0) / 0.05
            let decayElapsed = elapsed - tSwitch
            // T = 20 + 40 * e^(-0.005*t), slow cool-down
            temp = 20.0 + 40.0 * exp(-0.005 * decayElapsed)
          }
          let noise = Double.random(in: -0.05...0.05)
          continuation.yield(
            DiscoveredSensor(
              id: sensorID,
              name: "Mock Sensor",
              advertisedTemperature: temp + noise
            )
          )
          try? await Task.sleep(for: .seconds(1))
        }
    }
  }
#endif
