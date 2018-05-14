#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Wed May 31 09:14:08 2017

@author: omaier
"""

import pyopencl.array as clarray
import numpy as np
DTYPE = np.complex64


def bdiv_1(v,queue,dx=None,dy=None):

    if dx is None:
      dx = 1
    if dy is None:
      dy = 1

    n = v.shape[3]
    m = v.shape[2]
    k = v.shape[0]
    
    div_v = clarray.zeros(queue,(k,m,n),dtype=DTYPE)
    
    
    div_v[:,:,0] = v[:,0,:,0]/dx
    div_v[:,:,-1] = -v[:,0,:,-2]/dx
    div_v[:,:,1:-1] = (v[:,0,:,1:-1]-v[:,0,:,:-2])/dx
    
    div_v[:,0,:] = div_v[:,0,:] + v[:,1,0,:]/dy
    div_v[:,-1,:] = div_v[:,-1,:] - v[:,1,-2,:]/dy
    div_v[:,1:-1,:] = div_v[:,1:-1,:] + (v[:,1,1:-1,:] - v[:,1,:-2,:])/dy

    return div_v

def fgrad_1(u,queue,dx=None,dy=None):

    if dx is None:
      dx = 1
    if dy is None:
      dy = 1
    
    n = u.shape[2]
    m = u.shape[1]
    k = u.shape[0]
    
    grad = clarray.zeros(queue,(k,2,m,n),dtype=DTYPE)
     
    grad[:,0,:,:-1] = (u[:,:,1:] - u[:,:,:-1])/dx
    
    grad[:,1,:-1,:] = (u[:,1:,:] - u[:,:-1,:])/dy


    return grad
  
def fdiv_2(x,queue,dx=None,dy=None):

    if dx is None:
      dx = 1
    if dy is None:
      dy = 1
      
    (k,i,m,n) = x.shape
    
    div_x = clarray.zeros(queue,(k,2,m,n),dtype=DTYPE)
    
    div_x[:,0,:,:-1] = (x[:,0,:,1:]-x[:,0,:,:-1])/dx
    div_x[:,0,:-1,:]  = div_x[:,0,:-1,:] + (x[:,2,1:,:]-x[:,2,:-1,:])/dy
    
    div_x[:,1,:,:-1] = (x[:,2,:,1:]-x[:,2,:,:-1])/dx
    div_x[:,1,:-1,:] = div_x[:,1,:-1,:] + (x[:,1,1:,:]-x[:,1,:-1,:])/dy
    return div_x
    
def sym_bgrad_2(x,queue,dx=None,dy=None):

    if dx is None:
      dx = 1
    if dy is None:
      dy = 1
      
    (k,i,m,n) =x.shape
    
    grad_x = clarray.zeros(queue,(k,3,m,n),dtype=DTYPE)
    
    grad_x[:,0,:,0] =x[:,0,:,0]/dx
    grad_x[:,0,:,1:-1] = (x[:,0,:,1:-1] - x[:,0,:,:-2])/dx
    grad_x[:,0,:,-1] = -x[:,0,:,-2]/dx
    
    grad_x[:,1,0,:] = x[:,1,0,:]/dy
    grad_x[:,1,1:-1,:] = (x[:,1,1:-1,:]-x[:,1,:-2,:])/dy
    grad_x[:,1,-1,:] = -x[:,1,-2,:]/dy
    
    grad_x[:,2,0,:] = x[:,0,0,:]/dy
    grad_x[:,2,1:-1,:] = (x[:,0,1:-1,:]-x[:,0,:-2,:])/dy
    grad_x[:,2,-1,:] = -x[:,0,-2,:]/dy
    
    grad_x[:,2,:,0] = grad_x[:,2,:,0]+x[:,1,:,0]/dx
    grad_x[:,2,:,1:-1] = grad_x[:,2,:,1:-1] + (x[:,1,:,1:-1] - x[:,1,:,:-2])/dx
    grad_x[:,2,:,-1] = grad_x[:,2,:,-1] - x[:,1,:,-2]/dx
    
    grad_x[:,2,:,:] = grad_x[:,2,:,:]/2
    
    return grad_x  