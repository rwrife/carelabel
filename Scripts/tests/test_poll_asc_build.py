import struct
import unittest

from Scripts.poll_asc_build import der_to_raw, processing_state_result


class ProcessingStateTests(unittest.TestCase):
    def test_asc_valid_is_terminal_success(self) -> None:
        self.assertEqual(processing_state_result("VALID"), "success")

    def test_complete_is_retained_as_terminal_success(self) -> None:
        self.assertEqual(processing_state_result("COMPLETE"), "success")

    def test_failed_and_invalid_are_terminal_failures(self) -> None:
        self.assertEqual(processing_state_result("FAILED"), "failure")
        self.assertEqual(processing_state_result("INVALID"), "failure")

    def test_processing_and_unknown_remain_pending(self) -> None:
        self.assertEqual(processing_state_result("PROCESSING"), "pending")
        self.assertEqual(processing_state_result("UNKNOWN"), "pending")



def encode_der(r: bytes, s: bytes) -> bytes:
    def encode_int(value: bytes) -> bytes:
        if value[0] & 0x80:
            value = b"\x00" + value
        return bytes([0x02, len(value)]) + value

    body = encode_int(r) + encode_int(s)
    return bytes([0x30, len(body)]) + body


class DERToRawTests(unittest.TestCase):
    def test_simple_values_pad_to_32_bytes(self) -> None:
        r = (1).to_bytes(4, "big")
        s = (2).to_bytes(4, "big")
        der = encode_der(r, s)
        raw = der_to_raw(der)
        self.assertEqual(len(raw), 64)
        self.assertEqual(raw[:32], r.rjust(32, b"\x00"))
        self.assertEqual(raw[32:], s.rjust(32, b"\x00"))

    def test_high_bit_leading_zero_is_stripped(self) -> None:
        # A value whose top byte has the high bit set gets a leading 0x00
        # padding byte in DER (to keep it a positive integer). The parser
        # must remove that padding rather than keep the value 33 bytes long.
        r = bytes([0xFF]) * 32
        s = bytes([0x01]) * 32
        der = encode_der(r, s)
        raw = der_to_raw(der)
        self.assertEqual(len(raw), 64)
        self.assertEqual(raw[:32], r)
        self.assertEqual(raw[32:], s)

if __name__ == "__main__":
    unittest.main()
