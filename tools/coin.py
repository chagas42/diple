import math, struct, sys, wave

RATE = 22050
NOTES = [(987.77, 0.075), (1318.51, 0.42)]


def square(freq, t, duty=0.5):
    return 1.0 if (t * freq) % 1.0 < duty else -1.0


def main(path):
    samples = []
    for i, (freq, length) in enumerate(NOTES):
        n = int(RATE * length)
        for k in range(n):
            t = k / RATE
            decay = 1.0 if i == 0 else math.exp(-t * 7.5)
            attack = min(1.0, k / (RATE * 0.004))
            samples.append(0.28 * square(freq, t) * decay * attack)
    fade = int(RATE * 0.01)
    for k in range(fade):
        samples[-1 - k] *= k / fade
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Resources/Sounds/coin.wav")
