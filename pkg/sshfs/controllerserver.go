package sshfs

import ()

func NewControllerServer(driverInstance DriverInstance) *ControllerServer {
	return &ControllerServer{
		instance: &driverInstance,
	}
}

type ControllerServer struct {
	instance *DriverInstance
}
