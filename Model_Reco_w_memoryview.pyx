# cython: profile=True
# cython: infer_types=True
from __future__ import division
cimport cython
from cython.parallel import parallel, prange
cimport numpy as np
import numpy as np
import time
import VFA_model
import decimal
cimport gradients_divergences as gd
import matplotlib.pyplot as plt
plt.ion()
np.import_array()
DTYPE = np.complex128
ctypedef np.complex128_t DTYPE_t
from numpy cimport ndarray

cdef extern from "math.h":
    double sqrt(double z)


@cython.cdivision(True)      
@cython.boundscheck(False) # turn off bounds-checking for entire function
@cython.wraparound(False)  # turn off negative index wrapping for entire function    
@cython.initializedcheck(False)

cdef class Model_Reco:
  cdef dict __dict__
  cdef int unknowns
  cdef int NSlice
  cdef int NScan
  cdef int dimY
  cdef int dimX
  cdef int NC
  cdef DTYPE_t[:,:,:,::1] grad_x_2D
  cdef DTYPE_t[:,:,:,::1] conj_grad_x_2D
  cdef DTYPE_t[:,:,::1] Coils
  
  def __init__(self,par):
    self.par = par
    self.unknowns = par.unknowns
    self.NSlice = par.NSlice
    self.NScan = par.NScan
    self.dimX = par.dimX
    self.dimY = par.dimY
    self.NC = par.NC

    print("Please Set Parameters, Data and Initial images")

    
  cdef np.ndarray[DTYPE_t,ndim=3] irgn_solve_2D(self,np.ndarray[DTYPE_t,ndim=3] x, int iters,np.ndarray[DTYPE_t,ndim=4] data):
    

    ###################################
    ### Adjointness     
    xx = np.random.random_sample(np.shape(x)).astype('complex128')
    yy = np.random.random_sample(np.shape(data)).astype('complex128')
    a = np.vdot(xx.flatten(),np.ravel(self.operator_adjoint_2D(yy)))
    b = np.vdot(np.ravel(self.operator_forward_2D(xx)),yy.flatten())
    test = np.abs(a-b)
    print("test deriv-op-adjointness:\n <xx,DGHyy>=%05f %05fi\n <DGxx,yy>=%05f %05fi  \n adj: %.2E"  % (a.real,a.imag,b.real,b.imag,decimal.Decimal(test)))
    cdef np.ndarray[DTYPE_t,ndim=3] x_old = x
    a = self.FT(self.step_val[:,None,:,:]*self.Coils)
    b = self.operator_forward_2D(x)
    res = data - a + b
  
#    x = self.pdr_tgv_solve_2D(x,res,iters)
    x = self.tgv_solve_2D(x,res,iters)      
    fval= (self.irgn_par.lambd/2*np.linalg.norm(data - self.FT(self.step_val[:,None,:,:]*self.Coils))**2
           +self.irgn_par.gamma*np.sum(np.abs(gd.fgrad_1(x)-self.v))
           +self.irgn_par.gamma*(2)*np.sum(np.abs(gd.sym_bgrad_2(self.v))) 
           +1/(2*self.irgn_par.delta)*np.linalg.norm((x-x_old).flatten())**2)    
    print ("Function value after GN-Step: %f" %fval)

    return x
  
  cdef np.ndarray[DTYPE_t,ndim=4] irgn_solve_3D(self,np.ndarray[DTYPE_t,ndim=4] x,int iters,np.ndarray[DTYPE_t,ndim=4] data):
    

    ###################################
    ### Adjointness     
    xx = np.random.random_sample(np.shape(x)).astype('complex128')
    yy = np.random.random_sample(np.shape(data)).astype('complex128')
    a = np.vdot(xx.flatten(),self.operator_adjoint_3D(yy).flatten())
    b = np.vdot(self.operator_forward_3D(xx).flatten(),yy.flatten())
    test = np.abs(a-b)
    print("test deriv-op-adjointness:\n <xx,DGHyy>=%05f %05fi\n <DGxx,yy>=%05f %05fi  \n adj: %.2E"  % (a.real,a.imag,b.real,b.imag,decimal.Decimal(test)))
    cdef np.ndarray[DTYPE_t,ndim=4] x_old = x
    a = self.FT(self.step_val[:,None,:,:]*self.Coils)
    b = self.operator_forward_3D(x)
    res = data - a + b
    print("Test the norm: %2.2E  a=%2.2E   b=%2.2E" %(np.linalg.norm(res.flatten()),np.linalg.norm(a.flatten()), np.linalg.norm(b.flatten())))
  
    x = self.tgv_solve_3D(x,res,iters)
      
    fval= (self.irgn_par.lambd/2*np.linalg.norm(data - self.FT(self.step_val[:,None,:,:]*self.Coils))**2
           +self.irgn_par.gamma*np.sum(np.abs(gd.fgrad_3(x)-self.v))
           +self.irgn_par.gamma*(2)*np.sum(np.abs(gd.sym_bgrad_3(self.v))) 
           +1/(2*self.irgn_par.delta)*np.linalg.norm((x-x_old).flatten())**2)    
    print ("Function value after GN-Step: %f" %fval)

    return x
        

    
  cpdef execute_2D(self):
     
      self.FT = self.nFT_2D
      self.FTH = self.nFTH_2D
      iters = self.irgn_par.start_iters
      self.v = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype='complex128')
      
      self.result = np.zeros((self.irgn_par.max_GN_it,self.unknowns,self.par.NSlice,self.par.dimY,self.par.dimX),dtype='complex128')
      result = np.copy(self.model.guess)
      for islice in range(self.par.NSlice):
        self.Coils = np.squeeze(self.par.C[:,islice,:,:])        
        for i in range(self.irgn_par.max_GN_it):
          start = time.time()       
          self.step_val = self.model.execute_forward_2D(result[:,islice,:,:],islice)
          self.grad_x_2D = self.model.execute_gradient_2D(result[:,islice,:,:],islice)
          self.conj_grad_x_2D = np.conj(self.grad_x_2D)
          
          
          result[:,islice,:,:] = self.irgn_solve_2D(result[:,islice,:,:], iters, self.data[:,:,islice,:])
          self.result[i,:,islice,:,:] = result[:,islice,:,:]
          
          iters = np.fmin(iters*2,self.irgn_par.max_iters)
          self.irgn_par.gamma = self.irgn_par.gamma*0.8
          self.irgn_par.delta = self.irgn_par.delta*2
          
          end = time.time()-start
          print("Elapsed time: %f seconds" %end)
            
        
  cpdef execute_2D_cart(self):
   
    self.FT = self.FT_2D
    self.FTH = self.FTH_2D
    iters = self.irgn_par.start_iters
    self.v = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype='complex128')
  
    self.dimX = self.par.dimX
    self.dimY = self.par.dimY
    self.NSlice = self.par.NSlice
    self.NScan = self.par.NScan
    self.NC = self.par.NC
    self.unknowns = 2
    
    self.result = np.zeros((self.irgn_par.max_GN_it,self.unknowns,self.par.NSlice,self.par.dimY,self.par.dimX),dtype='complex128')
    result = np.copy(self.model.guess)
    for islice in range(self.par.NSlice):
      self.Coils = np.squeeze(self.par.C[:,islice,:,:])        
      for i in range(self.irgn_par.max_GN_it):
        start = time.time()       
        self.step_val = self.model.execute_forward_2D(result[:,islice,:,:],islice)
        self.grad_x_2D = self.model.execute_gradient_2D(result[:,islice,:,:],islice)
        self.conj_grad_x_2D = np.conj(self.grad_x_2D)
        
        
        result[:,islice,:,:] = self.irgn_solve_2D(result[:,islice,:,:], iters, self.data[:,:,islice,:,:])
        self.result[i,:,islice,:,:] = result[:,islice,:,:]
        
        iters = np.fmin(iters*2,self.irgn_par.max_iters)
        self.irgn_par.gamma = self.irgn_par.gamma*0.8
        self.irgn_par.delta = self.irgn_par.delta*2
        
        end = time.time()-start
        print("Elapsed time: %f seconds" %end)
                 
      
     
  cpdef execute_3D(self):
     
      self.FT = self.nFT_3D
      self.FTH = self.nFTH_3D
      iters = self.irgn_par.start_iters

      
      
      self.result = np.zeros((self.irgn_par.max_GN_it+1,self.unknowns,self.par.NSlice,self.par.dimY,self.par.dimX),dtype='complex128')
      self.result[0,:,:,:,:] = np.copy(self.model.guess)

      self.Coils = np.squeeze(self.par.C)        
      for i in range(self.irgn_par.max_GN_it):
        start = time.time()       
        self.step_val = self.model.execute_forward_3D(self.result[i,:,:,:,:])
        self.grad_x = self.model.execute_gradient_3D(self.result[i,:,:,:,:])
        self.conj_grad_x = np.conj(self.grad_x)
          
          
        self.result[i+1,:,:,:,:] = self.irgn_solve_3D(self.result[i,:,:,:,:], iters, self.data)


        iters = np.fmin(iters*2,self.irgn_par.max_iters)
        self.irgn_par.gamma = self.irgn_par.gamma*0.7
        self.irgn_par.delta = self.irgn_par.delta*2
          
        end = time.time()-start
        print("Elapsed time: %f seconds" %end)
            
               
      
  cdef  DTYPE_t[:,:,:,::1] operator_forward_2D(self,DTYPE_t[:,:,::1] x):
    cdef DTYPE_t[:,:,:,::1] tmp = np.zeros((self.NScan,self.NC,self.dimY,self.dimX),dtype=DTYPE)
    cdef int i,j,k,m,n,o
    with nogil, parallel():   
      for o in range(self.unknowns):   
        for i in range(self.NScan):
          for j in range(self.NC):
            for n in range(self.dimY):
              for m in prange(self.dimX):
                tmp[i,j,n,m] = tmp[i,j,n,m] + (x[o,n,m])*(self.grad_x_2D[o,i,n,m])*self.Coils[j,n,m]
      
    return (self.FT(np.asarray(tmp)))

    
  cdef DTYPE_t[:,:,::1] operator_adjoint_2D(self,DTYPE_t[:,:,:,::1] x):
    
    cdef DTYPE_t[:,:,:,::1] fdx = np.zeros((self.NScan,self.NC,self.dimY,self.dimX),dtype=DTYPE)
    fdx = self.FTH(np.asarray(x))
    cdef DTYPE_t[:,:,::1] dx = np.zeros((self.unknowns,self.par.dimX,self.par.dimY),dtype=DTYPE)
    cdef DTYPE_t[:,:,::1] conC = np.conj(self.Coils)

    cdef int i,j,k,m,n,o   
    with nogil, parallel():    
      for o in range(self.unknowns):   
        for i in range(self.NScan):
          for j in range(self.NC):
            for n in range(self.dimY):
              for m in prange(self.dimX):    
                dx[o,n,m] = dx[o,n,m] +(fdx[i,j,n,m]*conC[j,n,m]*self.conj_grad_x_2D[o,i,n,m])
    return (dx)   
  
  
  cdef np.ndarray[DTYPE_t,ndim=5] operator_forward_3D(self,np.ndarray[DTYPE_t,ndim=4] x):
    
    tmp = np.zeros_like(self.grad_x)
      
    for i in range(self.unknowns):
      tmp[i,:,:,:,:] = x[i,:,:,:]*self.grad_x[i,:,:,:,:]
      
    return self.FT(np.sum(tmp,axis=0)[:,None,:,:,:]*self.Coils)

    
  cdef np.ndarray[DTYPE_t,ndim=4] operator_adjoint_3D(self,np.ndarray[DTYPE_t,ndim=5] x):
    
    x[~np.isfinite(x)] = 1e-20
    fdx = self.FTH(x)
      
    fdx = np.squeeze(np.sum(fdx*np.conj(self.Coils),axis=1))
      
    cdef np.ndarray[DTYPE_t,ndim=4]dx = np.zeros((self.unknowns,self.par.NSlice,self.par.dimX,self.par.dimY),dtype=DTYPE)
    for i in range(self.unknowns):   
      dx[i,:,:,:] = np.sum(self.conj_grad_x[i,:,:,:,:]*fdx,axis=0)
      
    return dx    
    
  cpdef np.ndarray[DTYPE_t,ndim=3] tgv_solve_2D(self, DTYPE_t[:,:,::1] x, DTYPE_t[:,:,:,::1] res, int iters):
    cdef double alpha = self.irgn_par.gamma
    cdef double beta = self.irgn_par.gamma*2
    
    
    cdef double tau = 1/np.sqrt(16**2+8**2)
    cdef double tau_new = 0
    
    cdef DTYPE_t[:,:,::1] xk = x
    cdef DTYPE_t[:,:,::1] x_new = np.zeros_like(x,dtype=DTYPE)
    
    cdef DTYPE_t[:,:,:,::1] r = np.zeros_like(res,dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] z1 = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] z2 = np.zeros(([self.unknowns,3,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] v = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    
    cdef DTYPE_t[:,:,:,::1] r_new = np.zeros_like(res,dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] z1_new = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] z2_new = np.zeros(([self.unknowns,3,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] v_new = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    

    cdef DTYPE_t[:,:,::1] Kyk1 = np.zeros_like(x,dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] Kyk2 = np.zeros_like(z1,dtype=DTYPE)
    
    cdef DTYPE_t[:,:,:,::1] Ax = np.zeros_like(res,dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] Ax_Axold = np.zeros_like(res,dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] Axold = np.zeros_like(res,dtype=DTYPE)    
    cdef DTYPE_t[:,:,:,::1] tmp = np.zeros_like(res,dtype=DTYPE)    
    
    cdef DTYPE_t[:,:,::1] Kyk1_new = np.zeros_like(x,dtype=DTYPE)
    cdef DTYPE_t[:,:,:,::1] Kyk2_new = np.zeros_like(z1,dtype=DTYPE)
    
    
    cdef double delta = self.irgn_par.delta
    cdef double mu = 1/delta
    
    cdef double theta_line = 1.0

    
    cdef double beta_line = 1.0
    cdef double beta_new = 1.0
    
    cdef double mu_line = 0.8
    cdef double delta_line = 0.8
    cdef np.ndarray[DTYPE_t, ndim=2] scal = np.zeros((self.par.dimX,self.par.dimY),dtype=DTYPE)
    
    cdef double ynorm = 0.0
    cdef double lhs = 0.0

    cdef double primal = 0.0
    cdef double dual = 0.0
    cdef double gap = 0.0
    cdef double lambd = self.irgn_par.lambd

    
    cdef  DTYPE_t[:,:,:,::1] gradx = np.zeros_like(z1,dtype=DTYPE)
    cdef  DTYPE_t[:,:,:,::1] gradx_xold = np.zeros_like(z1,dtype=DTYPE)
    
    cdef  DTYPE_t[:,:,:,::1] v_vold = np.zeros_like(v,dtype=DTYPE)
    cdef  DTYPE_t[:,:,:,::1] symgrad_v = np.zeros_like(z2,dtype=DTYPE)
    cdef  DTYPE_t[:,:,:,::1] symgrad_v_vold = np.zeros_like(z2,dtype=DTYPE)
    
#    print('Test 1')
    Axold = self.operator_forward_2D(x)
    Kyk1 = self.sub_arr3(self.operator_adjoint_2D(r) , gd.bdiv_1(z1))
    Kyk2 = self.sub_arr4(self.negate4(z1) , gd.fdiv_2(z2))
    cdef int i=0
#    print('made it')
    for i in range(iters):
#      print('inner loop')
      np.maximum(0,np.asarray(self.div_scal3(self.add_arr3(self.sub_arr3(x , self.mult_scal3(tau,(Kyk1))),self.mult_scal3((tau/delta),xk)),(1+tau/delta))),np.asarray(x_new))

#      print('done')
      np.maximum(0,np.minimum(300/self.model.M0_sc,np.asarray(x_new[0,:,:]),np.asarray(x_new[0,:,:])),np.asarray(x_new[0,:,:]))
      np.abs(np.maximum(50/self.model.T1_sc,np.minimum(5000/self.model.T1_sc,np.asarray(x_new[1,:,:]),np.asarray(x_new[1,:,:])),np.asarray(x_new[1,:,:])),np.asarray(x_new[1,:,:]))

#      np.abs(x_new[1,:,:],x_new[1,:,:])
      
      
      v_new = self.sub_arr4(v,self.mult_scal(tau,Kyk2))
#      print('After primal update')   
#      print(np.asarray(v_new))
      
      
      beta_new = beta_line*(1+mu*tau)
      
#      print('update tau')
      tau_new = tau*sqrt(beta_line/beta_new*(1+theta_line))
#      tau_new = tau*np.sqrt((1+theta_line))     
      
      beta_line = beta_new
#      print('update beta')     
      
      gradx = gd.fgrad_1(x_new)
      gradx_xold = self.sub_arr4(gradx , gd.fgrad_1(x))
#      print('gradient update')
      v_vold = self.sub_arr4(v_new,v)
#      print('v update')
      symgrad_v = gd.sym_bgrad_2(v_new)
      symgrad_v_vold = self.sub_arr4(symgrad_v , gd.sym_bgrad_2(v))
#      print('symbgrad update')
      Ax = self.operator_forward_2D(x_new)
      Ax_Axold = self.sub_arr4(Ax,Axold)
#      print('Before While loop')
      while True:
        
        theta_line = tau_new/tau
        
        z1_new = self.add_arr4(z1 , self.mult_scal(beta_line*tau_new,( self.sub_arr4(self.add_arr4(gradx , self.mult_scal(theta_line,gradx_xold)) , self.add_arr4(v_new , self.mult_scal(theta_line,v_vold))  ))))
        z1_new = z1_new/np.maximum(1,(np.sqrt(np.sum(self.power4(z1_new,2),axis=(0,1)))/alpha))
     
        z2_new = self.add_arr4(z2 , self.mult_scal(beta_line*tau_new,( self.add_arr4(symgrad_v , self.mult_scal(theta_line,symgrad_v_vold )))))
        scal = np.sqrt( np.sum(self.add_arr3(self.add_arr3(self.power(z2_new[:,0,:,:],2) , self.power(z2_new[:,1,:,:],2)) , self.mult_scal3(2,self.power(z2_new[:,2,:,:],2))),axis=0) )
        np.maximum(1,scal/(beta),scal)
        z2_new = z2_new/scal
        
        
        
        tmp = self.add_arr4(Ax,self.mult_scal(theta_line,Ax_Axold))
        r_new = self.div_scal4(self.sub_arr4(self.add_arr4( r  , self.mult_scal(beta_line*tau_new,(tmp)) ) , self.mult_scal(beta_line*tau_new,res)),(1+beta_line*tau_new/lambd))
        
        Kyk1_new = self.sub_arr3(self.operator_adjoint_2D(r_new),gd.bdiv_1(z1_new))
        Kyk2_new = self.sub_arr4(self.negate4(z1_new) ,gd.fdiv_2(z2_new))

        
        ynorm = np.linalg.norm(np.concatenate([np.ravel(self.sub_arr4(r_new,r)),np.ravel(self.sub_arr4(z1_new,z1)),np.ravel(self.sub_arr4(z2_new,z2))]))
        lhs = np.sqrt(beta_line)*tau_new*np.linalg.norm(np.concatenate([np.ravel(self.sub_arr3(Kyk1_new,Kyk1)),np.ravel(self.sub_arr4(Kyk2_new,Kyk2))]))        
        if lhs <= ynorm:
            break
        else:
            tau_new = tau_new*mu_line
            
      Kyk1 = (Kyk1_new)
      Kyk2 =  (Kyk2_new)
      Axold =(Ax)
      z1 = (z1_new)
      z2 = (z2_new)
      r =  (r_new)
      tau =  (tau_new)
        
  
      x = x_new
      v = v_new
        
      if not np.mod(i,20):
        plt.figure(1)
        plt.imshow(np.transpose(np.abs(x[0,:,:])*self.model.M0_sc))
        plt.pause(0.05)
        plt.figure(2)
#        plt.imshow(np.transpose(np.abs(-self.par.TR/np.log(x[1,:,:]))),vmin=0,vmax=3000)
        plt.imshow(np.transpose(np.abs(x[1,:,:])*self.model.T1_sc),vmin=0,vmax=3000)
        plt.pause(0.05)
        primal= np.real(self.irgn_par.lambd/2*np.linalg.norm(np.ravel(self.sub_arr4(Ax,res)))**2+alpha*np.sum(np.abs(self.sub_arr4(gradx,v))) +
                 beta*np.sum(np.abs(symgrad_v)) + 1/(2*delta)*np.linalg.norm(np.ravel(self.sub_arr3(x,xk)))**2)
    
        dual = np.real(-delta/2*np.linalg.norm(np.ravel(self.negate(Kyk1_new)))**2 - np.vdot(np.ravel(xk),np.ravel(self.negate(Kyk1_new))) + np.sum(Kyk2_new) 
                - 1/(2*self.irgn_par.lambd)*np.linalg.norm(np.ravel(r))**2 - np.vdot(np.ravel(res),np.ravel(r)))
        gap = np.abs(primal - dual)
        print("Iteration: %d ---- Primal: %f, Dual: %f, Gap: %f "%(i,primal,dual,gap))
        
        
    self.v = np.asarray(v)
    return np.asarray(x)
  
  cdef np.ndarray[DTYPE_t,ndim=4] tgv_solve_3D(self, np.ndarray[DTYPE_t,ndim=4] x, np.ndarray[DTYPE_t,ndim=5] res, int iters):
    cdef double alpha = self.irgn_par.gamma
    cdef double beta = self.irgn_par.gamma*2
    
    
    cdef double tau = 1/np.sqrt(16**2+8**2)
    cdef np.ndarray[DTYPE_t,ndim=4] xk = x
    cdef np.ndarray[DTYPE_t,ndim=4] x_new = np.zeros_like(x,dtype=DTYPE)
    
    cdef np.ndarray[DTYPE_t,ndim=5] r = np.zeros_like(res,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] z1 = np.zeros(([self.unknowns,3,self.par.NSlice,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] z2 = np.zeros(([self.unknowns,6,self.par.NSlice,self.par.dimX,self.par.dimY]),dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] v = np.zeros_like(z1,dtype=DTYPE)
    
    cdef np.ndarray[DTYPE_t,ndim=5] r_new = np.zeros_like(r,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] z1_new = np.zeros_like(z1,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] z2_new = np.zeros_like(z2,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] v_new = np.zeros_like(v,dtype=DTYPE)
    

    cdef np.ndarray[DTYPE_t,ndim=4] Kyk1 = np.zeros_like(x,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] Kyk2 = np.zeros_like(z1,dtype=DTYPE)
    
    cdef np.ndarray[DTYPE_t,ndim=5] Ax = np.zeros_like(res,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] Ax_Axold = np.zeros_like(Ax,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] Axold = np.zeros_like(Ax,dtype=DTYPE)    
    cdef np.ndarray[DTYPE_t,ndim=5] tmp = np.zeros_like(Ax,dtype=DTYPE)    
    
    cdef np.ndarray[DTYPE_t,ndim=4] Kyk1_new = np.zeros_like(Kyk1,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] Kyk2_new = np.zeros_like(Kyk2,dtype=DTYPE)
    
    
    cdef double delta = self.irgn_par.delta
    cdef double mu = 1/delta
    
    cdef double theta_line = 1
    cdef double beta_line = 1
    cdef double mu_line = 0.5
    cdef np.ndarray[DTYPE_t,ndim=3] scal = np.zeros((self.par.NSlice,self.par.dimX,self.par.dimY),dtype=DTYPE)
    
    cdef double ynorm = 0
    cdef double lhs = 0

    cdef double primal = 0
    cdef double dual = 0
    cdef double gap = 0

    
    cdef np.ndarray[DTYPE_t,ndim=5] gradx = np.zeros_like(z1,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] gradx_xold = np.zeros_like(z1,dtype=DTYPE)
    
    cdef np.ndarray[DTYPE_t,ndim=5] v_vold = np.zeros_like(v,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] symgrad_v = np.zeros_like(z2,dtype=DTYPE)
    cdef np.ndarray[DTYPE_t,ndim=5] symgrad_v_vold = np.zeros_like(z2,dtype=DTYPE)
    
    Axold = self.operator_forward_3D(x)
    Kyk1 = self.operator_adjoint_3D(r) - gd.bdiv_3(z1)
    Kyk2 = -z1 - gd.fdiv_3(z2)
    cdef int i=0
    
    for i in range(iters):
      np.maximum(0,((x - tau*(Kyk1))+(tau/delta)*xk)/(1+tau/delta),x_new)
      
      
      np.maximum(0,np.minimum(300/self.model.M0_sc,x_new[0,:,:,:],x_new[0,:,:,:]),x_new[0,:,:,:])
      np.abs(np.maximum(50/self.model.T1_sc,np.minimum(5000/self.model.T1_sc,
                                                       x_new[1,:,:,:],x_new[1,:,:,:]),
                                                       x_new[1,:,:,:]),x_new[1,:,:,:])

#      np.abs(x_new[1,:,:],x_new[1,:,:])
      
      
      v_new = v-tau*Kyk2
      
      beta_new = beta_line*(1+mu*tau)
      
      tau_new = tau*np.sqrt(beta_line/beta_new*(1+theta_line))
      beta_line = beta_new
      
      gradx = gd.fgrad_3(x_new)
      gradx_xold = gradx - gd.fgrad_3(x)
      v_vold = v_new-v
      symgrad_v = gd.sym_bgrad_3(v_new)
      symgrad_v_vold = symgrad_v - gd.sym_bgrad_3(v)
      Ax = self.operator_forward_3D(x_new)
      Ax_Axold = Ax-Axold
    
      while True:
        
        theta_line = tau_new/tau
        
        z1_new = z1 + beta_line*tau_new*( gradx + theta_line*gradx_xold - v_new - theta_line*v_vold  )
        z1_new = z1_new/np.maximum(1,(np.sqrt(np.sum(z1_new**2,axis=(0,1)))/alpha))
     
        z2_new = z2 + beta_line*tau_new*( symgrad_v + theta_line*symgrad_v_vold )
        scal = np.sqrt( np.sum(z2_new[:,0,:,:,:]**2 + z2_new[:,1,:,:,:]**2 +
                    z2_new[:,2,:,:,:]**2+ 2*z2_new[:,3,:,:,:]**2 + 
                    2*z2_new[:,4,:,:,:]**2+2*z2_new[:,5,:,:,:]**2,axis=0))
        np.maximum(1,scal/(beta),scal)
        z2_new = z2_new/scal
        
        
        
        tmp = Ax+theta_line*Ax_Axold
        r_new = (( r  + beta_line*tau_new*(tmp) ) - beta_line*tau_new*res)/(1+beta_line*tau_new/self.irgn_par.lambd)
        
        Kyk1_new = self.operator_adjoint_3D(r_new)-gd.bdiv_3(z1_new)
        Kyk2_new = -z1_new -gd.fdiv_3(z2_new)

        
        ynorm = np.linalg.norm(np.concatenate([(r_new-r).flatten(),(z1_new-z1).flatten(),(z2_new-z2).flatten()]))
        lhs = np.sqrt(beta_line)*tau_new*np.linalg.norm(np.concatenate([(Kyk1_new-Kyk1).flatten(),(Kyk2_new-Kyk2).flatten()]))        
        if lhs <= ynorm:
            break
        else:
            tau_new = tau_new*mu_line
            
      Kyk1 = (Kyk1_new)
      Kyk2 =  (Kyk2_new)
      Axold =(Ax)
      z1 = (z1_new)
      z2 = (z2_new)
      r =  (r_new)
      tau =  (tau_new)
        
  
      x = x_new
      v = v_new
        
      if not np.mod(i,20):
        plt.figure(1)
        plt.imshow(np.transpose(np.abs(x[0,0,:,:]*self.model.M0_sc)))
        plt.pause(0.05)
        plt.figure(2)
        plt.imshow(np.transpose(np.abs(x[1,0,:,:]*self.model.T1_sc)),vmin=0,vmax=3000)
#        plt.imshow(np.transpose(np.abs(x[1,0,:,:]*self.model.T1_sc)),vmin=0,vmax=3000)
        plt.pause(0.05)
        primal= np.real(self.irgn_par.lambd/2*np.linalg.norm((Ax-res).flatten())**2+alpha*np.sum(np.abs((gradx-v))) +
                 beta*np.sum(np.abs(symgrad_v)) + 1/(2*delta)*np.linalg.norm((x-xk).flatten())**2)
    
        dual = np.real(-delta/2*np.linalg.norm((-Kyk1_new).flatten())**2 - np.vdot(xk.flatten(),(-Kyk1_new).flatten()) + np.sum(Kyk2_new) 
                - 1/(2*self.irgn_par.lambd)*np.linalg.norm(r.flatten())**2 - np.vdot(res.flatten(),r.flatten()))
        gap = np.abs(primal - dual)
        print("Iteration: %d ---- Primal: %f, Dual: %f, Gap: %f "%(i,primal,dual,gap))
        
        
    self.v = np.asarray(v)
    return np.asarray(x)
  
  
  
  cpdef np.ndarray[DTYPE_t,ndim=4] FT_2D(self,np.ndarray[DTYPE_t,ndim=4] x):

#    cdef int nscan = np.shape(x)[0]
#    cdef int NC = np.shape(x)[1]
#    cdef float scale =  np.sqrt(np.shape(x)[2]*np.shape(x)[3])
#        
#    cdef np.ndarray result = np.zeros_like(x,dtype=DTYPE)
##    cdef int scan=0
##    cdef int coil=0
#    for scan in range(nscan):
#      for coil in range(NC):
#        result[scan,coil,:,:] = self.fft_forward(x[scan,coil,:,:])/scale
      
    return self.fft_forward(x)/np.sqrt(np.shape(x)[2]*np.shape(x)[3])
 
  
  
      
  cpdef np.ndarray[DTYPE_t,ndim=4] FTH_2D(self,np.ndarray[DTYPE_t,ndim=4] x):
#    cdef int nscan = np.shape(x)[0]
#    cdef int NC = np.shape(x)[1]
#    cdef float scale =  np.sqrt(np.shape(x)[2]*np.shape(x)[3])
#        
#    cdef np.ndarray result = np.zeros_like(x,dtype=DTYPE)
##    cdef int scan=0
##    cdef int coil=0
#    for scan in range(nscan):
#      for coil in range(NC):
#        result[scan,coil,:,:] = self.fft_back(x[scan,coil,:,:])*scale
      
    return self.fft_back(x)*np.sqrt(np.shape(x)[2]*np.shape(x)[3])


  cpdef np.ndarray[DTYPE_t,ndim=4] nFT_2D(self, np.ndarray[DTYPE_t,ndim=4] x):

    cdef int nscan = np.shape(x)[0]
    cdef int NC = np.shape(x)[1]   
    cdef np.ndarray[DTYPE_t,ndim=3] result = np.zeros((nscan,NC,self.par.Nproj*self.par.N),dtype=DTYPE)
    cdef np.ndarray[np.float64_t,ndim=1] dcf = np.sqrt(self.dcf.flatten())
    cdef double scal = np.sqrt(self.par.dimX*self.par.dimY)
    for scan in range(nscan):
      for coil in range(NC):
          self.nfftplan[scan][coil].f_hat = x[scan,coil,:,:]/scal
          result[scan,coil,:] = self.nfftplan[scan][coil].trafo()
      
    return np.reshape(result*dcf,[nscan,NC,self.par.Nproj,self.par.N])



  cpdef np.ndarray[DTYPE_t,ndim=4] nFTH_2D(self, np.ndarray[DTYPE_t,ndim=4] x):
    cdef int nscan = np.shape(x)[0]
    cdef int NC = np.shape(x)[1]     
    cdef np.ndarray[DTYPE_t,ndim=4] result = np.zeros((nscan,NC,self.par.dimX,self.par.dimY),dtype=DTYPE)
    x = x*np.sqrt(self.dcf)
    for scan in range(nscan):
        for coil in range(NC):  
            self.nfftplan[scan][coil].f = x[scan,coil,:,:]
            result[scan,coil,:,:] = self.nfftplan[scan][coil].adjoint()
      
    return result/np.sqrt(self.par.dimX*self.par.dimY)
      
  
  
  cpdef nFT_3D(self, np.ndarray[DTYPE_t,ndim=5] x):

    cdef int nscan = np.shape(x)[0]
    cdef int NC = np.shape(x)[1]   
    cdef int NSlice = self.par.NSlice
    cdef int dimX = self.par.dimX
    cdef int dimY = self.par.dimY
    cdef np.ndarray[DTYPE_t,ndim=4] result = np.zeros((nscan,NC,NSlice,self.par.Nproj*self.par.N),dtype=DTYPE)
    cdef int scan=0
    cdef int coil=0
    cdef int islice=0
    cdef np.ndarray[np.float64_t,ndim=1] dcf = np.sqrt(self.dcf.flatten())
    for scan in range(nscan):
      for coil in range(NC):
        for islice in range(NSlice):
          self.nfftplan[scan][coil].f_hat = x[scan,coil,islice,:,:]/np.sqrt(dimX*dimY)
          result[scan,coil,islice,:,:] = self.nfftplan[scan][coil].trafo()*dcf
      
    return np.reshape(result,[nscan,NC,NSlice,self.par.Nproj,self.par.N])



  cpdef nFTH_3D(self, np.ndarray[DTYPE_t,ndim=5] x):
    cdef int nscan = np.shape(x)[0]
    cdef int NC = np.shape(x)[1]  
    cdef int NSlice = self.par.NSlice
    cdef int dimX = self.par.dimX
    cdef int dimY = self.par.dimY
    cdef np.ndarray[DTYPE_t,ndim=5]   result = np.zeros((nscan,NC,NSlice,dimX,dimY),dtype='complex128')
    cdef int scan=0
    cdef int coil=0
    cdef int islice=0    
    for scan in range(nscan):
        for coil in range(NC): 
          for islice in range(NSlice):
            self.nfftplan[scan][coil].f = x[scan,coil,islice,:,:]*np.sqrt(self.dcf)
            result[scan,coil,islice,:,:] = self.nfftplan[scan][coil].adjoint()
      
    return result/np.sqrt(dimX*dimY)  






#  cdef pdr_tgv_solve_2D(self, np.ndarray[DTYPE_t, ndim=3] x, np.ndarray[DTYPE_t, ndim=3] res, int iters):
#    
#    
#
#    
#    cdef double alpha = self.irgn_par.gamma
#    cdef double beta = self.irgn_par.gamma*2
#    
#    cdef double delta = self.irgn_par.delta
#    cdef double gamma1 = 1/delta    
#    
#
#    
#    cdef double sigma0 = 1   
#    cdef double tau0 = 15   
#    
#    cdef double L = 0
#    
#    ##estimate operator norm using power iteration
#    cdef np.ndarray[DTYPE_t, ndim=3] xx = np.random.random_sample(np.shape(x)).astype('complex128')
#    cdef np.ndarray[DTYPE_t, ndim=3] yy = 1+sigma0*tau0*self.operator_adjoint_2D(self.operator_forward_2D(xx));
#    for i in range(10):
#       if not np.isclose(np.linalg.norm(yy.flatten()),0):
#           xx = yy/np.linalg.norm(yy.flatten())
#       else:
#           xx = yy
#       yy = 1+sigma0*tau0*self.operator_adjoint_2D(self.operator_forward_2D(xx))
#       l1 = np.vdot(yy.flatten(),xx.flatten());
#    L = np.max(np.abs(l1)) ## Lipschitz constant estimate   
#    cdef double L1 = np.max(np.abs(self.grad_x[0,:,None,:,:]*np.asarray(self.Coils)
#                                   *np.conj(self.grad_x[0,:,None,:,:])*np.conj(self.Coils)))
#    cdef double L2 = np.max(np.abs(self.grad_x[1,:,None,:,:]*np.asarray(self.Coils)
#                                   *np.conj(self.grad_x[1,:,None,:,:])*np.conj(self.Coils)))
#
##    L = np.max((L1,L2))*self.unknowns*self.par.NScan*self.par.NC*sigma0*tau0+1
#    L = np.sqrt(L**2+8+16) + (4*sigma0*tau0)**2/(1+4*sigma0*tau0)
#    print("Operatornorm estimate L1: %f ---- L2: %f -----  L: %f "%(L1,L2,L))    
#    cdef double gamma = 2*gamma1/L   
#    
#    cdef double theta = 1/np.sqrt(1+sigma0*gamma)
#
#    
#    cdef double sigma = sigma0
#    cdef double tau = tau0 
#
#    
#    cdef np.ndarray[DTYPE_t, ndim=3] xk = x
#    cdef np.ndarray[DTYPE_t, ndim=3] xhat = x    
#    cdef np.ndarray[DTYPE_t, ndim=4] v = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)    
#    cdef np.ndarray[DTYPE_t, ndim=4] vhat = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)   
#    
#    cdef np.ndarray[DTYPE_t, ndim=3] r = np.zeros_like(res,dtype=DTYPE)
#    cdef np.ndarray[DTYPE_t, ndim=4] z1 = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)
#    cdef np.ndarray[DTYPE_t, ndim=4] z2 = np.zeros(([self.unknowns,3,self.par.dimX,self.par.dimY]),dtype=DTYPE)
#
#    cdef np.ndarray[DTYPE_t, ndim=3] rhat = np.zeros_like(res,dtype=DTYPE)
#    cdef np.ndarray[DTYPE_t, ndim=4] z1hat = np.zeros(([self.unknowns,2,self.par.dimX,self.par.dimY]),dtype=DTYPE)
#    cdef np.ndarray[DTYPE_t, ndim=4] z2hat = np.zeros(([self.unknowns,3,self.par.dimX,self.par.dimY]),dtype=DTYPE)
#    
#
#    cdef np.ndarray[DTYPE_t, ndim=3] Kd1 = np.zeros_like(res,dtype=DTYPE)
#    cdef np.ndarray[DTYPE_t, ndim=4] Kd2 = np.zeros_like(z1,dtype=DTYPE)
#    cdef np.ndarray[DTYPE_t, ndim=4] Kd3 = np.zeros_like(z2,dtype=DTYPE)
#    
#    
#    cdef np.ndarray[DTYPE_t, ndim=3] b1 = np.zeros_like(x,dtype=DTYPE)    
#    cdef np.ndarray[DTYPE_t, ndim=4] b2 = np.zeros_like(v,dtype=DTYPE)
#    
#    cdef np.ndarray[DTYPE_t, ndim=3] d1 = np.zeros_like(x,dtype=DTYPE)      
#    cdef np.ndarray[DTYPE_t, ndim=4] d2 = np.zeros_like(v,dtype=DTYPE)
#                   
#    cdef np.ndarray[DTYPE_t, ndim=3] T1 = np.zeros_like(d1,dtype=DTYPE)    
#    cdef np.ndarray[DTYPE_t, ndim=4] T2 = np.zeros_like(d2,dtype=DTYPE)                      
#
#    cdef np.ndarray[DTYPE_t, ndim=2] scal = np.zeros((self.par.dimX,self.par.dimY),dtype=DTYPE)
#
#
#    cdef double primal = 0
#    cdef double dual = 0
#    cdef double gap = 0
#
#
#
#    i=0
#    for i in range(iters):
#      
#      #### Prox (id+sigma F) of x_hat
#      np.maximum(0,(xhat+(sigma/delta)*xk)/(1+sigma/delta),x)
#      np.minimum(300/self.model.M0_sc,x[0,:,:],x[0,:,:])
#      np.abs(np.minimum(5000/self.model.T1_sc,x[1,:,:],x[1,:,:]),x[1,:,:])
#      v = vhat
#      
#      
#      #### Prox (id+tau G) of y_hat
#      r = ( rhat - tau*res)/(1+tau/self.irgn_par.lambd)        
#      z1 = z1hat/np.maximum(1,(np.sqrt(np.sum(z1hat**2,axis=(0,1)))/alpha))
#      scal = np.sqrt( np.sum(z2hat[:,0,:,:]**2 + z2hat[:,1,:,:]**2 + 2*z2hat[:,2,:,:]**2,axis=0) )
#      np.maximum(1,scal/(beta),scal)
#      z2 = z2hat/scal      
#  
#      
#      
#      #### update b
#      #### Accelerated Version
#      b1 = ((1+theta)*x-theta*xhat) - sigma*(self.operator_adjoint_2D((1+theta)*r-rhat) - gd.bdiv_1((1+theta)*z1-z1hat))
#      b2 = ((1+theta)*v-theta*vhat) - sigma*(-((1+theta)*z1-z1hat) - gd.fdiv_2((1+theta)*z2-z2hat))
#      ### normal Version
##      b1 = (2*x-theta*xhat) - sigma*(self.operator_adjoint_2D(2*r-rhat) - gd.bdiv_1(2*z1-z1hat))
##      b2 = (2*v-theta*vhat) - sigma*(-(2*z1-z1hat) - gd.fdiv_2(2*z2-z2hat))          
#          
#      #### update d
#      Kd1 = (self.operator_forward_2D(d1))
#      Kd2 = (gd.fgrad_1(d1)-d2)
#      Kd3 = (gd.sym_bgrad_2(d2))
#      
#      T1 = d1 + sigma0*tau0*(self.operator_adjoint_2D(Kd1) - gd.bdiv_1(Kd2))
#      T2 = d2 + sigma0*tau0*(-Kd2 - gd.fdiv_2(Kd3))
#      
#      d1 = d1 + 1/L*(b1-T1)
#      d2 = d2 + 1/L*(b2-T2)
#      
#      #### Accelerated Version
#      xhat = theta*(xhat-x) + d1
#      vhat = theta*(vhat-v) + d2
#      #### normal Version
##      xhat = (xhat-x) + d1
##      vhat = (vhat-v) + d2      
#      #### Accelerated Version      
#      rhat = r + 1/theta*tau*(self.operator_forward_2D(d1))
#      z1hat = z1 + 1/theta*tau*(gd.fgrad_1(d1)-d2)
#      z2hat = z2 + 1/theta*tau*(gd.sym_bgrad_2(d2))
#      #### normal Version
##      rhat = r + tau*(self.operator_forward_2D(d1))
##      z1hat = z1 + tau*(gd.fgrad_1(d1)-d2)
##      z2hat = z2 + tau*(gd.sym_bgrad_2(d2))
#      #### Accelerated Version      
#      sigma = theta*sigma
#      tau = 1/theta*tau
#      theta = 1/np.sqrt(1+sigma*gamma)
#      
#        
#      if not np.mod(i,1):
#        plt.figure(1)
#        plt.imshow(np.transpose(np.abs(x[0,:,:]*self.model.M0_sc)))
#        plt.pause(0.05)
#        plt.figure(2)
##        plt.imshow(np.transpose(np.abs(-self.par.TR/np.log(x[1,:,:]))),vmin=0,vmax=3000)
#        plt.imshow(np.transpose(np.abs(x[1,:,:]*self.model.T1_sc)),vmin=0,vmax=3000)
#        plt.pause(0.05)
#        primal= np.real(self.irgn_par.lambd/2*np.linalg.norm((self.operator_forward_2D(x)-res).flatten())**2+alpha*np.sum(np.abs((gd.fgrad_1(x)-v))) +
#                 beta*np.sum(np.abs(gd.sym_bgrad_2(v))) + 1/(2*delta)*np.linalg.norm((x-xk).flatten())**2)
#        
#
#        dual = np.real(-delta/2*np.linalg.norm(-(self.operator_adjoint_2D(r)-gd.bdiv_1(z1)).flatten())**2 
#             - np.vdot(xk.flatten(),-(self.operator_adjoint_2D(r)-gd.bdiv_1(z1)).flatten()) + np.sum(-z1 -gd.fdiv_2(z2)) 
#             - 1/(2*self.irgn_par.lambd)*np.linalg.norm(r.flatten())**2 - np.vdot(res.flatten(),r.flatten()))
#        gap = np.abs(primal - dual)
#        print("Iteration: %d ---- Primal: %f, Dual: %f, Gap: %f "%(i,primal,dual,gap))
#        
#        
#    self.v = v
#    return x  
#  
  cdef DTYPE_t[:,:,:,::1] mult_arr(self,DTYPE_t[:,:,:,::1] a, DTYPE_t[:,:,:,::1] b):
    cdef int i,j,k,l
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    nl = a.shape[3]    
    cdef DTYPE_t[:,:,:,::1] out = np.empty((ni,nj,nk,nl),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in range(nk):
            for l in prange(nl):
              out[i,j,k,l] = a[i,j,k,l]*b[i,j,k,l]
    return out
    
  cdef DTYPE_t[:,:,:,::1] mult_scal(self,DTYPE_t b, DTYPE_t[:,:,:,::1] a):
    cdef int i,j,k,l
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    nl = a.shape[3]    
    cdef DTYPE_t[:,:,:,::1] out = np.empty((ni,nj,nk,nl),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in range(nk):
            for l in prange(nl):
              out[i,j,k,l] = a[i,j,k,l]*b
    return out  
    
  cdef DTYPE_t[:,:,::1] mult_scal3(self,DTYPE_t b, DTYPE_t[:,:,::1] a):
    cdef int i,j,k
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    cdef DTYPE_t[:,:,::1] out = np.empty((ni,nj,nk),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in prange(nk):
              out[i,j,k] = a[i,j,k]*b
    return out  
    
  cdef DTYPE_t[:,:,::1] negate(self,DTYPE_t[:,:,::1] a):
    cdef int i,j,k
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]  
    cdef DTYPE_t[:,:,::1] out = np.empty((ni,nj,nk),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in prange(nk):
            out[i,j,k] = -a[i,j,k]
    return out
  
  cdef DTYPE_t[:,:,:,::1] negate4(self,DTYPE_t[:,:,:,::1] a):
    cdef int i,j,k,l
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    nl = a.shape[3]    
    cdef DTYPE_t[:,:,:,::1] out = np.empty((ni,nj,nk,nl),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in range(nk):
            for l in prange(nl):
              out[i,j,k,l] = -a[i,j,k,l]
    return out
    
  
  cdef DTYPE_t[:,:,::1] sub_arr3(self,DTYPE_t[:,:,::1] a, DTYPE_t[:,:,::1] b):
#    print('In Sub3')
    cdef int i,j,k
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    cdef DTYPE_t[:,:,::1] out = np.empty((ni,nj,nk),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in prange(nk):
              out[i,j,k] = a[i,j,k]-b[i,j,k]  
#    print('After For')
    return out             
  cdef DTYPE_t[:,:,:,::1] sub_arr4(self,DTYPE_t[:,:,:,::1] a, DTYPE_t[:,:,:,::1] b):
#    print('In Sub4')
    cdef int i,j,k,l
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    nl = a.shape[3]    
    cdef DTYPE_t[:,:,:,::1] out = np.empty((ni,nj,nk,nl),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in range(nk):
            for l in prange(nl):
              out[i,j,k,l] = a[i,j,k,l]-b[i,j,k,l]   
#    print('After For')             
    return out    
  cdef DTYPE_t[:,:,::1] power(self,DTYPE_t[:,:,::1] a, cython.numeric b):
    cdef int i,j,k
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2] 
    cdef DTYPE_t[:,:,::1] out = np.empty((ni,nj,nk),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in prange(nk):
              out[i,j,k] = a[i,j,k]**b
    return out     
  
  cdef DTYPE_t[:,:,:,::1] power4(self,DTYPE_t[:,:,:,::1] a, cython.numeric b):
    cdef int i,j,k,l
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    nl = a.shape[3]    
    cdef DTYPE_t[:,:,:,::1] out = np.empty((ni,nj,nk,nl),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in range(nk):
            for l in prange(nl):
              out[i,j,k,l] = a[i,j,k,l]**b
    return out       
  
  cdef DTYPE_t[:,:,:,::1] add_arr4(self,DTYPE_t[:,:,:,::1] a, DTYPE_t[:,:,:,::1] b):
    cdef int i,j,k,l
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    nl = a.shape[3]    
    cdef DTYPE_t[:,:,:,::1] out = np.empty((ni,nj,nk,nl),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in range(nk):
            for l in prange(nl):
              out[i,j,k,l] = a[i,j,k,l]+b[i,j,k,l]   
    return out  
  
  cdef DTYPE_t[:,:,::1] add_arr3(self,DTYPE_t[:,:,::1] a, DTYPE_t[:,:,::1] b):
#    print('in add3')
    cdef int i,j,k
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2] 
    cdef DTYPE_t[:,:,::1] out = np.empty((ni,nj,nk),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in prange(nk):
              out[i,j,k] = a[i,j,k]+b[i,j,k]  
#    print('add done')          
    return out   
  cdef DTYPE_t[:,:,::1] div_scal3(self,DTYPE_t[:,:,::1] a,DTYPE_t b):
#    print('in div3')
    cdef int i,j,k
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]  
    cdef DTYPE_t[:,:,::1] out = np.empty((ni,nj,nk),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in prange(nk):
              out[i,j,k] = a[i,j,k]/b
#    print('div done')          
    return out   
  cdef DTYPE_t[:,:,:,::1] div_scal4(self,DTYPE_t[:,:,:,::1] a,DTYPE_t b):
    cdef int i,j,k,l
    ni = a.shape[0]
    nj = a.shape[1]
    nk = a.shape[2]
    nl = a.shape[3]    
    cdef DTYPE_t[:,:,:,::1] out = np.empty((ni,nj,nk,nl),dtype=DTYPE)
    with nogil, parallel():
      for i in range(ni):
        for j in range(nj):
          for k in range(nk):
            for l in prange(nl):
              out[i,j,k,l] = a[i,j,k,l]/b
    return out     