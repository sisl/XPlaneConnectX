import struct
import socket
import threading
import datetime
import time
from typing import Tuple
import pandas as pd

class XPlaneConnectX():
    def __init__(self,ip:str='127.0.0.1',port:int=49000) -> None:
        """XPlaneConnectX class initialization.

        Args:
            ip (str, optional): IP address where X-Plane can be found. Defaults to '127.0.0.1'.
            port (int, optional): Port to communicate with X-Plane. This can be found and changed in the X-Plane network settings. Defaults to 49000.
        
        Example:
            xpc = XPlaneConnectX()  # Uses default IP and port
            xpc = XPlaneConnectX(ip="192.168.1.10", port=50000) # Custom IP and port
        """
        
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(('', 0))
        if hasattr(socket, 'SIO_UDP_CONNRESET'):
            self.sock.ioctl(socket.SIO_UDP_CONNRESET, 0)
        self.ip = ip
        self.port = port
        self.reverse_index = {}
        self.current_dref_values = {}
        
    
    def subscribeDREFs(self, subscribed_drefs:list[Tuple[str,int]], history:float=0.0, timeout:float=5.0, retry_interval:float=0.5) -> None:
        """Permanently subscribe to a list of DataRefs with a certain frequency. This is the prefered method for obtaining
        the most up to date values for DataRefs that will be used a large number of times during the runtime of your code.
        Examples include the position, velocity or attitude. The data will be asynchronously received and processed. This is
        is different than the `getDREF` or `getPOSI` method that run synchronously. The most recently value for each subscribed
        DataRef is stored in XPlaneConnectX.current_dref_values which is a dictionary with the DataRefs as keys. Each entry of
        the dictionary contains another dictionary with the keys *value* and "timestamp* containing the most recent value of
        DataRef as well as the time it was received, respectiveley.

        This method blocks until an initial value has been received for every subscribed DataRef. Because X-Plane uses UDP for
        both the subscription requests and the data stream, individual packets may be dropped when many DataRefs are subscribed
        at once. To recover from lost subscription packets, this method re-sends the RREF request for any DataRef that has not
        responded within `retry_interval` seconds, until every DataRef has produced a value or `timeout` seconds elapse. If some
        DataRefs still have not responded after `timeout`, a `TimeoutError` is raised listing the offending names (typically a
        misspelled or unknown DataRef). Passing `timeout <= 0` disables the blocking wait entirely.

        Args:
            subscribed_drefs (list[Tuple[str,int]]): List of (DataRef, frequency) tuples to be permanently observed. Example: [("sim/cockpit2/controls/brake_fan_on", 2), ("sim/flightmodel/position/y_agl",10)].
            history  (float): How many seconds of history to keep in buffer. Applications for this include for example the moving average filters.
            timeout (float): Total seconds to wait for initial values for every subscribed DataRef. Defaults to 5.0. A non-positive value disables the blocking wait.
            retry_interval (float): Seconds between retransmissions of RREF requests for DataRefs that have not yet responded. Defaults to 0.5.

        Example:
            xpc = XPlaneConnectX()
            xpc.subscribeDREFs([("sim/cockpit2/controls/brake_fan_on", 2), ("sim/flightmodel/position/y_agl", 10)])
        """

        self.subscribed_drefs = subscribed_drefs
        self.recording_in_progress = False
        self.recorded_data = {}
        self.history = history

        # initialize the current data dictionary that always contains the most up-to-date data received from the simulator
        self.reverse_index = {i:sdf[0] for i,sdf in enumerate(self.subscribed_drefs)}
        self.current_dref_values = {sdf[0]:{'value':None, 'timestamp':None, "history":[]} for sdf in self.subscribed_drefs}

        # start the receiver before sending any RREF so no response can beat the reader
        self._observe_async()
        self._create_observation_requests()

        if timeout > 0:
            self._wait_for_initial_values(timeout=timeout, retry_interval=retry_interval)

    def _send_rref(self, idx:int, dref:str, freq:int) -> None:
        msg = struct.pack("<4sxii400s", b'RREF', freq, idx, dref.encode('utf-8'))
        self.sock.sendto(msg, (self.ip, self.port))

    def _create_observation_requests(self, indices=None) -> None:
        if indices is None:
            indices = range(len(self.subscribed_drefs))
        for i in indices:
            dref, freq = self.subscribed_drefs[i]
            self._send_rref(i, dref, freq)

    def _wait_for_initial_values(self, timeout:float, retry_interval:float) -> None:
        # freq==0 is an unsubscribe request and will never be acknowledged; exclude from the wait set
        pending = {i for i, (_, freq) in enumerate(self.subscribed_drefs) if freq > 0}
        deadline = time.monotonic() + timeout
        next_retry = time.monotonic() + retry_interval
        poll_interval = min(0.05, retry_interval / 4) if retry_interval > 0 else 0.05
        while True:
            pending = {i for i in pending
                       if self.current_dref_values[self.reverse_index[i]]['value'] is None}
            if not pending:
                return
            now = time.monotonic()
            if now >= deadline:
                missing = sorted({self.reverse_index[i] for i in pending})
                raise TimeoutError(
                    f"subscribeDREFs: {len(missing)} DataRef(s) did not respond within "
                    f"{timeout}s. Check the names (possibly misspelled or unknown to X-Plane):\n  - "
                    + "\n  - ".join(missing)
                )
            if now >= next_retry:
                self._create_observation_requests(indices=pending)
                next_retry = now + retry_interval
            sleep_for = min(poll_interval, max(0.0, deadline - now), max(0.0, next_retry - now))
            time.sleep(max(sleep_for, 0.0))
                    
    def _observe(self) -> None:
        while True:
            try:
                data, addr = self.sock.recvfrom(16348)
            except ConnectionResetError:
                continue
            header = data[0:4]
            if header[0:4] == b'RREF':
                if ((len(data)-5)%8) != 0:
                    raise ValueError("Received data is not 8 bytes long")
                no_packets = int((len(data)-5) / 8)
                for p_idx in range(no_packets):
                    p_data = data[(5+p_idx*8):(5+(p_idx+1)*8)]
                    idx, value = struct.unpack("<if", p_data)
                    if idx in self.reverse_index.keys():    # if not in self.reverse_idx, the received packet is for the getDREF method or a stale subscription
                        # write current values to the self.current_dref_values dictionary
                        dref_dict = {'value':value, 'timestamp':datetime.datetime.now()}

                        # add current value to history and prune history data that is older than self.history
                        history = [dref_dict] + self.current_dref_values[self.reverse_index[idx]]['history']
                        history = [x for x in history if x["timestamp"] >= history[0]["timestamp"] - datetime.timedelta(seconds=self.history)]

                        self.current_dref_values[self.reverse_index[idx]] = {**dref_dict, 'history':history}

                        # save off if recording is in progress
                        if self.recording_in_progress:
                            self.recorded_data[self.reverse_index[idx]].append(dref_dict)
    
    def _observe_async(self) -> None:
        observe_thread = threading.Thread(target=self._observe)
        observe_thread.daemon = True
        observe_thread.start()
    
    def startRECORDING(self) -> None:
        """Starts a recording of the subscribed DataRefs into self.recorded_data. Data is stored in self.recored_data. See `stopRECORDING` for the format the data is saved in self.recorded_data.
        
        Example:
            xpc = XPlaneConnectX()
            xpc.subscribeDREFs([("sim/cockpit2/controls/brake_fan_on", 2),  # brake fan at 2Hz
                                ("sim/flightmodel/position/y_agl", 10)])    # altitude above ground at 10Hz
            xpc.startRECORDING()  # start the recording of data
            # ... do something else
            xpc.startRECORDING()  # Will display a warning and the current recording in progress will be overwritten.
        """
        if self.recording_in_progress:
            print("Warning: Recording was interrupted by the start of a new recording. Data from the previous recording is lost.")
        
        self.recorded_data = {dref[0]:[] for dref in self.subscribed_drefs}
        self.recording_in_progress = True
    
    def stopRECORDING(self, synchronize=False) -> dict:
        """
        Terminates the recording and returns a dictionary of lists that contain the recorded 
        values for the subscribed DataRefs along with the timestamp when they were received.

        Parameters:
            synchronize : bool, or float, optional
                - False: return raw unsynchronized data (default)
                - True: synchronize to lowest subscribed frequency
                - float: synchronize to specified frequency in Hz

        Returns:
            dict or pd.DataFrame
                Dictionary with DataRefs as keys and lists of dicts with 'value' and 'timestamp' 
                keys, or synchronized DataFrame if synchronize is specified

        Example:
            xpc = XPlaneConnectX()
            xpc.subscribeDREFs([("sim/cockpit2/controls/brake_fan_on", 2),   # brake fan at 2Hz
                                ("sim/flightmodel/position/y_agl", 10)])      # altitude above ground at 10Hz
            xpc.startRECORDING()  # start the recording of data
            # ... do something else
            data = xpc.stopRECORDING()  # data is returned as dictionary
        """
        if not self.recording_in_progress:
            raise RuntimeError("Recording was not started before it was stopped.")
        
        self.recording_in_progress = False
        
        if not synchronize:
            return self.recorded_data
        
        elif type(synchronize) in [float, int]:
            return self._synchronize_measurements(self.recorded_data, target_frequency_hz=synchronize)
        
        # default to the lowest frequency in subscribed_drefs
        elif synchronize == True:
            freq = min([sdf[1] for sdf in self.subscribed_drefs])
            return self._synchronize_measurements(self.recorded_data, target_frequency_hz=freq)

    def _synchronize_measurements(self, data_dict, target_frequency_hz=10):
        """
        Synchronize measurements from multiple sensors to a common frequency.
        
        Parameters:
        -----------
        data_dict : dict
            Dictionary where keys are column names and values are lists of dicts
            with 'value' and 'timestamp' keys
        target_frequency_hz : float
            Target frequency in Hz
        
        Returns:
        --------
        pd.DataFrame
            Synchronized dataframe with timestamp index
        """
        
        # Check if the requested synchronizing frequency is higher than lowest frequency in subscribed DataRefs
        if target_frequency_hz > min([sdr[1] for sdr in self.subscribed_drefs]):
            print("Warning: Requested DataRef frequency is higher than the minimum subscribed DataRef frequency.")

        # Convert each sensor's data to a DataFrame
        dfs = {}
        for column_name, measurements in data_dict.items():
            if not measurements:  # Skip empty lists
                continue
                
            df = pd.DataFrame(measurements)
            df['timestamp'] = pd.to_datetime(df['timestamp'])
            df = df.set_index('timestamp')
            df = df.rename(columns={'value': column_name})
            dfs[column_name] = df
        
        if not dfs:
            return pd.DataFrame()
        
        # Find the overall time range
        all_times = {}
        for df in dfs.keys():
            all_times[df] = dfs[df].index.tolist()
        
        start_time = max([min(all_times[k]) for k in all_times.keys()]) # choose the latest start time to avoid extrapolation on any df
        end_time = min([max(all_times[k]) for k in all_times.keys()])   # choose the ealiest stop time to avoid extrapolation on any df
        
        # Create a common time index at the target frequency
        target_frequency_str = str(int(1/target_frequency_hz * 10**9)) + 'ns'
        common_index = pd.date_range(start=start_time, end=end_time, 
                                    freq=target_frequency_str)
        
        # Resample and interpolate each column
        synchronized_dfs = []
        for column_name, df in dfs.items():
            # Reindex to common time grid and interpolate
            resampled = df.reindex(df.index.union(common_index)).interpolate(method='time').loc[common_index]
            synchronized_dfs.append(resampled)
        
        # Combine all columns
        result = pd.concat(synchronized_dfs, axis=1)
        result.index.name = 'timestamp'
        
        return result
        
    def getDREF(self, dref:str) -> float:
        """Gets the current value of a DataRef. This is only intended for one-time use. For datarefs with frequent use, consider using the permanently observed DataRefs that can be setup when initializing the XPlaneConnectX object.

        Args:
            dref (str): DataRef to be queried.

        Returns:
            float: Value of the DataRef `dref`.
        
        Example:
            xpc = XPlaneConnectX()
            value = xpc.getDREF(""sim/cockpit2/controls/brake_fan_on")
        """
        
        temp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        idx = len(list(self.reverse_index.keys()))+10   # set the index to the highest index of the permanently observed DataRefs + 10
        msg = struct.pack("<4sxii400s", b'RREF', 10, idx, dref.encode('utf-8'))   
        temp_socket.sendto(msg, (self.ip, self.port))

        data, addr = temp_socket.recvfrom(16348)
        idx_received, value= struct.unpack("<if", data[5:])
        if idx_received != idx:
            raise ValueError("Invalid index received.")
            
        # unsubscribe from the DataRef
        msg = struct.pack("<4sxii400s", b"RREF", 0, idx, dref.encode('utf-8'))   
        temp_socket.sendto(msg, (self.ip, self.port))
        
        return value
    
    def sendDREF(self, dref:str, value:float) -> None:
        """Writes a value to the specified DataRef provided that the DataRef is writable.

        Args:
            dref (str): DataRef to be changed.
            value (float): Value the DataRef should be set to.
        
        Example:
            xpc = XPlaneConnectX()
            xpc.sendDREF("sim/cockpit/electrical/landing_lights_on", 1) # Turn on the landing lights
        """
        
        msg = struct.pack('<4sxf500s', b'DREF', value, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
    
    def sendCMND(self, command:str) -> None:
        """Sends simulator commands to the simulator. These are not commands for the airplanes, but commands to operate the simulator (e.g., close X-Plane or take a screenshot)

        Args:
            command (str): Command to be executed.
        
        Example:
            xpc = XPlaneConnectX()
            xpc.sendCMND("sim/operation/quit")  # Example command to close X-Plane 
        """
        
        msg = struct.pack('<4sx500s', b'CMND', command.encode('utf-8'))
        self.sock.sendto(msg, (self.ip, self.port))
    
    def sendPOSI(self, lat:float, lon:float, elev:float, phi:float, theta:float, psi_true:float, ac:int=0) -> None:
        """Sets the global position of airplanes as well as their attitude. Note that this is the only option to set 
        the latitude and longitude of an airplane as the latitude and longititde DataRefs are not writiable.

        Args:
            lat (float): Latitude in degrees. For precise placement of an aircraft, this needs to be double precision.
            lon (float): Longitude in degrees. For precise placement of an aircraft, this needs to be double precision.
            elev (float): Altitude above mean sea level in meters.
            phi (float): Roll angle in degrees.
            theta (float): Pitch angle in degrees.
            psi_true (float): True heading (not magnetic) in degrees.
            ac (int, optional): Index of the aircraft you want to set the position of. 0 is the ego aircraft. Defaults to 0.
        
        Example:
            xpc = XPlaneConnectX()
            xpc.sendPOSI(37.7749, -122.4194, 100.0, 0.0, 0.0, 90.0)
        """
        
        msg = struct.pack('<4sxidddfff', b'VEHS',
                          ac,
                          lat,
                          lon,
                          elev,
                          psi_true,
                          theta,
                          phi)
        self.sock.sendto(msg, (self.ip, self.port))
        self.sock.sendto(msg, (self.ip, self.port)) # send twice since the elevation is erroneously calculated based on initial location
    
    def getPOSI(self) -> Tuple[float,float,float,float,float,float,float,float,float,float,float,float,float]:
        """Gets the global position of the ego aircraft. If frequently needed, consider using the permanently observed DataRefs that can be setup when initializing the XPlaneConnectX object.
        The following DataRefs are equivalent to the values returned by this method:
        
        sim/flightmodel/position/longitude 
        sim/flightmodel/position/latitidue
        sim/flightmodel/position/elevation 
        sim/flightmodel/position/y_agl 
        sim/flightmodel/position/true_theta
        sim/flightmodel/position/true_psi
        sim/flightmodel/position/true_phi
        sim/flightmodel/position/local_vx
        sim/flightmodel/position/local_vy
        sim/flightmodel/position/local_vz
        sim/flightmodel/position/Prad
        sim/flightmodel/position/Qrad
        sim/flightmodel/position/Rrad

        Returns:
            Tuple[float,float,float,float,float,float,float,float,float,float,float,float,float]: latitude in degrees, longitude in degrees, 
            elevation above mean sea level in meters, elevation above the terrain in meters, roll angle in degrees, pitch angle in degrees,
            true (not magnetic) heading in degrees, speed in east direction in meters per second (OpenGL coordinate system x-axis),
            speed in up direction in meters per second (OpenGL coordinate system y-axis), speed in south direction in meters per second (OpenGL coordinate system z-axis),
            roll rate in radians per second, pitch rate in radians per second, yaw rate in radians per second
        
        Example:
            xpc = XPlaneConnectX()
            lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r = xpc.getPOSI()
        """
        
        temp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        msg = struct.pack('4sx10s', b'RPOS', b'100')    # request at 100Hz, this should be sufficiently low enough latency for most use cases
        temp_socket.sendto(msg, (self.ip, self.port))
        received = False
        while not received:
            data, addr = temp_socket.recvfrom(16348)
            if data[0:4] == b'RPOS':
                (lon,         # longitude in degrees
                lat,          # latitude in degrees
                ele,          # elevation above mean sea level in meters
                y_agl,        # elevation above the terrain in meters
                theta,        # pitch angle in degrees
                psi_true,     # true hheading in degrees
                phi,          # roll angle in degrees
                vx,           # speed in east direction in meters per second (OpenGL coordinate system x-axis, intertial)
                vy,           # speed in up direction in meters per second (OpenGL coordinate system y-axis, intertial)
                vz,           # speed in south direction in meters per second (OpenGL coordinate system z-axis, intertial)
                p,            # roll rate in radians per second
                q,            # pitch rate in radians per second
                r,            # yaw rate in radians per second
                ) = struct.unpack("<xdddffffffffff", data[4:])
                
                # unsubscribe from RPOS
                msg = struct.pack('4sx10s', b'RPOS', b'0')    # setting the frequency to 0
                self.sock.sendto(msg, (self.ip, self.port))
                
                return lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r
            
            else:
                raise ValueError("Received invalid header.")
            
    
    def sendCTRL(self, lat_control:float, lon_control:float, rudder_control:float, throttle:float, gear:int, flaps:float, speedbrakes:float, park_brake:float) -> None:
        """Send basic controls to the ego aircraft. There are hundreds of DataRefs that provide more fine-grained control. These can be set through the setDREF method.

        Args:
            lat_control (float): Lateral pilot input, i.e., yoke rotation, or side stick left/right position. Ranges from [-1...1].
            lon_control (float): Longitudinal pilot input, i.e., yoke and side stick forward/backward position. Ranges from [-1...1].
            rudder_control (float): Rudder pilor input. Ranges from [-1...1].
            throttle (float): Throttle position. Ranges from [-1...1] with -1 being full reverse thrust, and 1 being full forward thrust.
            gear (int): Requested gear position. 0 corresponds to gear up, and 1 corresponds to gear down.
            flaps (float): Requested flaps position. Ranges from [0...1].
            speedbrakes (float): Requested speedbakes position. Possible values are {-0.5, [0...1]} where -0.5 means the speedbrake is armed, 0 is retracted, and 1 is fully deployed.
            park_brake (float): Requested park brake ratio. Ranged from [0...1]
        
        Example:
            xpc = XPlaneConnectX()
            xpc.sendCTRL(lat_control=-0.2, lon_control=0.0, rudder_control=0.2, throttle=0.8, gear=1, flaps=0.5, speedbrakes=0, park_brake=0)
        """
        
        # lateral control
        dref = "sim/cockpit2/controls/yoke_roll_ratio"
        msg = struct.pack('<4sxf500s', b'DREF', lat_control, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))     
        
        # longitudinal control
        dref = "sim/cockpit2/controls/yoke_pitch_ratio"
        msg = struct.pack('<4sxf500s', b'DREF', lon_control, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
        
        # rudder control
        dref = "sim/cockpit2/controls/yoke_heading_ratio"
        msg = struct.pack('<4sxf500s', b'DREF', rudder_control, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
        
        # throttle
        dref = "sim/cockpit2/engine/actuators/throttle_jet_rev_ratio_all"
        msg = struct.pack('<4sxf500s', b'DREF', throttle, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
        
        # gear
        dref = "sim/cockpit/switches/gear_handle_status"
        msg = struct.pack('<4sxf500s', b'DREF', gear, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
        
        # flaps
        # dref = "sim/cockpit2/controls/flap_handle_request_ratio" #this only for X-Plane 12.0+
        dref = "sim/cockpit2/controls/flap_ratio"
        msg = struct.pack('<4sxf500s', b'DREF', flaps, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
        
        # speedbrakes
        dref = "sim/cockpit2/controls/speedbrake_ratio"
        msg = struct.pack('<4sxf500s', b'DREF', speedbrakes, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))
        
        # park brake
        dref = "sim/cockpit2/controls/parking_brake_ratio"
        msg = struct.pack('<4sxf500s', b'DREF', park_brake, dref.encode('UTF-8'))
        self.sock.sendto(msg, (self.ip, self.port))

    
    def pauseSIM(self, set_pause:bool) -> None:
        """Pauses the simulator.

        Args:
            set_pause (bool): If `True`, the simulator is paused, if `False`, the simulator is unpaused.
        
        Example:
            xpc = XPlaneConnectX()
            xpc.pauseSIM(True)  # Pauses the simulator
            xpc.pauseSIM(False) # Unpauses the simulator
        """
        if set_pause:
            self.sendCMND('sim/operation/pause_on')
        else:
            self.sendCMND('sim/operation/pause_off')   
