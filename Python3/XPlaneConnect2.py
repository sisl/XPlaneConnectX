import struct
import socket
import time
import threading
import datetime


class XPlaneConnect2():
    def __init__(self,observed_drefs=[],ip='127.0.0.1',port=49000):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.ip = ip
        self.port = port
        self.observed_drefs = observed_drefs
        
        # initialize the current data dictionary that always contains the most up-to-date data received from the simulator
        self.reverse_index = {i:odf[0] for i,odf in enumerate(self.observed_drefs)}
        self.current_data = {odf[0]:{'value':None, 'timestamp':None} for odf in self.observed_drefs}
        
        self._create_observation_requests()
        self.observe()
    
    def _create_observation_requests(self):
        for i,odf in enumerate(self.observed_drefs):
            dref = odf[0]
            cmd = b'RREF'  # "Request DREF"
            freq = odf[1]     
            msg = struct.pack("<4sxii400s", cmd, freq, i, dref.encode('utf-8'))
            self.sock.sendto(msg, (self.ip, self.port))
            time.sleep(0.05)
            
            
    def _observe(self):
        while True:
            data, addr = self.sock.recvfrom(2048)
            header = data[0:4]
            if header[0:4] != b'RREF':
                raise ValueError("Unknown packet")
            if ((len(data)-5)%8) != 0:
                raise ValueError("Received data is not 8 bytes long")
            no_packets = int((len(data)-5) / 8)
            for p_idx in range(no_packets):
                p_data = data[(5+p_idx*8):(5+(p_idx+1)*8)]
                idx, value = struct.unpack("<if", p_data)
                # write current values to the self.current_data dictionary
                self.current_data[self.reverse_index[idx]] = {'value':value, 'timestamp':datetime.datetime.now()}
    
    def observe(self):
        observe_thread = threading.Thread(target=self._observe)
        observe_thread.daemon = True
        observe_thread.start()
    
    def set_dref(self, dref, value):
        msg = struct.pack('<4sxf500s', b'DREF', value, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
    
    def send_cmnd(self, command):
        msg = struct.pack('<4sx500s', b'CMND', command.encode('utf-8'))
        self.sock.sendto(msg, (self.ip, self.port))
    
    def pause(self, set_pause):
        if set_pause:
            self.send_cmnd('sim/operation/pause_on')
        else:
            self.send_cmnd('sim/operation/pause_off')   
