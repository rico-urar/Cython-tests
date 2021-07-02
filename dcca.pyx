import numpy as np
cimport numpy as np
cimport cython
from cython.parallel import prange
import ctypes
import pickle
import warnings
from . import dfa

cdef extern from "cLoops.h" nogil:
    double flucDCCAAbsCompute(double *y1, double *y2, double *t, int curr_win_size, int N, int pol_ord)
    double flucDCCANoAbsCompute(double *y1, double *y2, double *t, int curr_win_size, int N, int pol_ord)
    double flucDCCAForwAbsComputeNoOverlap(double *y1, double *y2, double *t, int curr_win_size, int N, int pol_ord);
    double flucDCCAForwBackwAbsComputeNoOverlap(double *y1, double *y2, double *t, int curr_win_size, int N, int pol_ord);
    double flucDCCAForwNoAbsComputeNoOverlap(double *y1, double *y2, double *t, int curr_win_size, int N, int pol_ord);
    double flucDCCAForwBackwNoAbsComputeNoOverlap(double *y1, double *y2, double *t, int curr_win_size, int N, int pol_ord);

cdef class DCCA:
    """Detrended Cross-Correlation Analysis class.

    Parameters
    ----------
    n : numpy ndarray
        Array of window's sizes used for the computation.
    tsVec1 : iterable
        First time series used for the analysis.
    tsVec2 : iterable
        Second time series used for the analysis.
    F : numpy ndarray
        Array containing the values of the fluctuations in each window.
    nRho : numpy ndarray
        Array of window's sizes used for the computation of `rho`.
    rho : numpy ndarray
        Array containing the cross-correlation index in each window.
    nThr : numpy ndarray
        Array of window's sizes used for the computation of `rho` thresholds.
    confUp : numpy ndarray
        Array containing the first confidence interval in each window.
    confDown : numpy ndarray
        Array containing the second confidence interval in each window.
    isComputed : bool
        Boolean value to know if `F` has been computed in order to prevent the
        computation of other functions that need `F`.
    """

    cdef:
        np.ndarray n, nRho, nThr
        np.ndarray tsVec1, tsVec2, F, rho, confUp, confDown
        bint isComputed

    def __init__(self, tsVec1=[], tsVec2=[]):
        if (isinstance(tsVec1, list) or isinstance(tsVec1, np.ndarray)) and (isinstance(tsVec2, list) or isinstance(tsVec2, np.ndarray)):
            if len(tsVec1) != 0 and len(tsVec2) != 0:
                self.tsVec1 = np.array(tsVec1, dtype=float)
                self.tsVec1 = self.tsVec1[~np.isnan(self.tsVec1)]
                self.tsVec2 = np.array(tsVec2, dtype=float)
                self.tsVec2 = self.tsVec2[~np.isnan(self.tsVec2)]
                if len(self.tsVec1) != len(self.tsVec2):
                    warnings.warn("Warning: Input vectors have different length. The longest vector has been reduced to the size of the shortest one.")
                    self.tsVec1 = self.tsVec1[0:np.min([len(self.tsVec1), len(self.tsVec2)])]
                    self.tsVec2 = self.tsVec2[0:np.min([len(self.tsVec1), len(self.tsVec2)])]
            self.isComputed = False
        elif isinstance(tsVec1, str) and len(tsVec2) == 0:
            if len(tsVec1.split('.')) > 1 and tsVec1.split('.')[-1] == 'fathon':
                f = open(tsVec1, 'rb')
                data = pickle.load(f)
                f.close()
                if data['kind'] != 'dcca':
                    raise ValueError('Error: Loaded object is not a DCCA object.')
                else:
                    self.tsVec1 = np.array(data['tsVec1'], dtype=float)
                    self.tsVec2 = np.array(data['tsVec2'], dtype=float)
                    self.n = np.array(data['n'], dtype=ctypes.c_int)
                    self.F = np.array(data['F'], dtype=ctypes.c_double)
                    self.isComputed = data['isComputed']
            else:
                raise ValueError('Error: Not recognized extension.')
        else:
           raise ValueError('Error: Wrong inputs, expected two arrays or a single string.') 

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cdef cy_flucCompute(self, np.ndarray[np.float64_t, ndim=1, mode='c'] vects1, np.ndarray[np.float64_t, ndim=1, mode='c'] vects2, np.ndarray[int, ndim=1, mode='c'] vecn, np.ndarray[np.float64_t, ndim=1, mode='c'] vecf, int polOrd, bint absVals, bint overlap, bint revSeg):
        cdef int nLen, tsLen
        cdef Py_ssize_t i, j
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] t

        nLen = len(vecn)
        tsLen = len(vects1)
        
        t = np.empty((tsLen, ), dtype=ctypes.c_double)
        for j in prange(tsLen, nogil=True):
            t[j] = float(j) + 1.0
        
        with nogil:
            if absVals:
                if overlap:
                    for i in range(nLen):
                        vecf[i] = flucDCCAAbsCompute(&vects1[0], &vects2[0], &t[0], vecn[i], tsLen, polOrd)
                else:
                    if revSeg:
                        for i in range(nLen):
                            vecf[i] = flucDCCAForwBackwAbsComputeNoOverlap(&vects1[0], &vects2[0], &t[0], vecn[i], tsLen, polOrd)
                    else:
                        for i in range(nLen):
                            vecf[i] = flucDCCAForwAbsComputeNoOverlap(&vects1[0], &vects2[0], &t[0], vecn[i], tsLen, polOrd)
            else:
                if overlap:
                    for i in range(nLen):
                        vecf[i] = flucDCCANoAbsCompute(&vects1[0], &vects2[0], &t[0], vecn[i], tsLen, polOrd)
                else:
                    if revSeg:
                        for i in range(nLen):
                            vecf[i] = flucDCCAForwBackwNoAbsComputeNoOverlap(&vects1[0], &vects2[0], &t[0], vecn[i], tsLen, polOrd)
                    else:
                        for i in range(nLen):
                            vecf[i] = flucDCCAForwNoAbsComputeNoOverlap(&vects1[0], &vects2[0], &t[0], vecn[i], tsLen, polOrd)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cpdef computeFlucVec(self, np.ndarray[np.int64_t, ndim=1, mode='c'] winSizes, int polOrd=1, bint absVals=True, bint overlap=False, bint revSeg=False):
        """Computation of the fluctuations in each window.

        Parameters
        ----------
        winSizes : numpy ndarray
            Array of window's sizes.
        polOrd : int, optional
            Order of the polynomial to be fitted in each window (default : 1).
        absVals : bool, optional
            If True, the computation of `F` is performed using the abolute values of
            the fluctuations of both `tsVec1` and `tsVec2` (default : True).
        overlap : bool, optional
            If True, computes `F` using overlapping segments (default : False).
        revSeg : bool, optional
            If True, the computation of `F` is repeated starting from the end of
            the time series, ignored if `overlap` is True (default : False).

        Returns
        -------
        numpy ndarray
            Array `n` of window's sizes.
        numpy ndarray
            Array `F` containing the values of the fluctuations in each window.
        """
        cdef int tsLen = len(self.tsVec1)

        if polOrd < 1:
            raise ValueError('Error: Polynomial order must be greater than 0.')
        if len(winSizes) > 1:
            if winSizes[len(winSizes)-1] <= winSizes[0]:
                raise ValueError('Error: `winSizes[-1]` must be greater than variable `winSizes[0]`.')
        if winSizes[len(winSizes)-1] > tsLen:
            raise ValueError('Error: `winSizes[-1]` must be smaller than the input vector length.')
        if winSizes[0] < (polOrd + 2):
            raise ValueError('Error: `winSizes[0]` must be at least equal to {}.'.format(polOrd + 2))

        self.n = np.array(winSizes, dtype=ctypes.c_int)
        self.F = np.zeros((len(self.n), ), dtype=ctypes.c_double)
        self.cy_flucCompute(np.array(self.tsVec1, dtype=ctypes.c_double), np.array(self.tsVec2, dtype=ctypes.c_double),
                            self.n, self.F, polOrd, absVals, overlap, revSeg)
        self.isComputed = True
        
        return self.n, self.F

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cdef computeFlucVecSameTs(self, np.ndarray[np.float64_t, ndim=1, mode='c'] vec, np.ndarray[int, ndim=1, mode='c'] wins, int polOrd, bint overlap, bint revSeg):
        cdef int nLen, tsLen = len(vec)
        cdef Py_ssize_t i, j
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] F_same
        cdef np.ndarray[int, ndim=1, mode='c'] vecn
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] t

        vecn = np.array(wins, dtype=ctypes.c_int)
        nLen = len(vecn)
        F_same = np.zeros((nLen, ), dtype=ctypes.c_double)
        
        t = np.empty((tsLen, ), dtype=ctypes.c_double)
        for j in prange(tsLen, nogil=True):
            t[j] = float(j) + 1.0
        
        with nogil:
            if overlap:
                for i in range(nLen):
                    F_same[i] = flucDCCAAbsCompute(&vec[0], &vec[0], &t[0], vecn[i], tsLen, polOrd)
            else:
                if revSeg:
                    for i in range(nLen):
                        F_same[i] = flucDCCAForwBackwAbsComputeNoOverlap(&vec[0], &vec[0], &t[0], vecn[i], tsLen, polOrd)
                else:
                    for i in range(nLen):
                        F_same[i] = flucDCCAForwAbsComputeNoOverlap(&vec[0], &vec[0], &t[0], vecn[i], tsLen, polOrd)
                
        return F_same

    @cython.boundscheck(False)
    @cython.nonecheck(False)
    cpdef fitFlucVec(self, int nStart=-999, int nEnd=-999, float logBase=np.e, bint verbose=False):
        """Fit of the fluctuations values.

        Parameters
        ----------
        nStart : int, optional
            Size of the smaller window used to fit `F` (default : first value of `n`).
        nEnd : int, optional
            Size of the bigger window used to fit `F` (default : last value of `n`).
        logBase : float, optional
            Base of the logarithm for the log-log fit of `n` vs `F` (default : e).
        verbose : bool, optional
            Verbosity (default : False).

        Returns
        -------
        float
            Slope of the fit.
        float
            Intercept of the fit.
        """
        cdef int start, end
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] log_fit

        if len(self.n) > 1:
            if self.isComputed:
                if nStart == -999:
                    nStart = self.n[0]
                if nEnd == -999:
                    nEnd = self.n[-1]
                if nStart > nEnd:
                    raise ValueError('Error: Variable nEnd must be greater than variable nStart.')
                if (nStart < self.n[0]) or (nEnd > self.n[-1]):
                    raise ValueError('Error: Fit limits must be included in interval [{}, {}].'.format(self.n[0], self.n[-1]))
                if (nStart not in self.n) or (nEnd not in self.n):
                    raise ValueError('Error: Fit limits must be included in the n vector.')

                start = np.where(self.n==nStart)[0][0]
                end = np.where(self.n==nEnd)[0][0]
                log_fit = np.polyfit(np.log(self.n[start:end+1]) / np.log(logBase), np.log(self.F[start:end+1]) / np.log(logBase), 1)
            
                if verbose:
                    print('Fit limits: [{}, {}]'.format(nStart, nEnd))
                    print('Fit result: H intercept = {:.2f}, H = {:.2f}'.format(log_fit[1], log_fit[0]))
                
                return log_fit[0], log_fit[1]
            else:
                print('Nothing to fit, fluctuations vector has not been computed yet.')
        else:
            print('At least two points are required.')

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cpdef multiFitFlucVec(self, np.ndarray[np.int_t, ndim=2, mode='c'] limitsList, float logBase=np.e, bint verbose=False):
        """Fit of the fluctuations values in different intervals at the same time.

        Parameters
        ----------
        limitsList : numpy ndarray
            kx2 array with the sizes of k starting and ending windows used to fit `F`.
        logBase : float, optional
            Base of the logarithm for the log-log fit of `n` vs `F` (default : e).
        verbose : bool, optional
            Verbosity (default : False).

        Returns
        -------
        numpy ndarray
            Slopes of the fits.
        numpy ndarray
            Intercepts of the fits.
        """
        cdef Py_ssize_t i
        cdef int limLen = len(limitsList)
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] list_H_intercept, list_H

        if self.isComputed:
            list_H = np.zeros((limLen, ), dtype=float)
            list_H_intercept = np.zeros((limLen, ), dtype=float)
            
            for i in range(limLen):
                if verbose:
                    print('----------')
                list_H[i], list_H_intercept[i] = self.fitFlucVec(nStart=limitsList[i][0], nEnd=limitsList[i][1],
                                                                 logBase=logBase, verbose=verbose)
            
            if verbose:
                print('----------')
                
            return list_H, list_H_intercept
        else:
            print('Nothing to fit, fluctuations vector has not been computed yet.')

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cpdef computeRho(self, np.ndarray[np.int64_t, ndim=1, mode='c'] winSizes, int polOrd=1, bint verbose=False, bint overlap=False, bint revSeg=False):
        """Computation of the cross-correlation index in each window.

        Parameters
        ----------
        winSizes : numpy ndarray
            Array of window's sizes.
        polOrd : int, optional
            Order of the polynomial to be fitted in each window (default : 1).
        verbose : bool, optional
            Verbosity (default : False).
        overlap : bool, optional
            If True, computes `F` using overlapping segments (default : False).
        revSeg : bool, optional
            If True, the computation of `F` is repeated starting from the end of
            the time series, ignored if `overlap` is True (default : False).

        Returns
        -------
        numpy ndarray
            Array of window's sizes.
        numpy ndarray
            Array containing the cross-correlation index.
        """
        cdef Py_ssize_t i
        cdef int nLen, tsLen = len(self.tsVec1)
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] Fxy, Fxx, Fyy

        if polOrd < 1:
            raise ValueError('Error: Polynomial order must be greater than 0.')
        if len(winSizes) > 1:
            if winSizes[len(winSizes)-1] <= winSizes[0]:
                raise ValueError('Error: `winSizes[-1]` must be greater than variable `winSizes[0]`.')
        if winSizes[len(winSizes)-1] > tsLen:
            raise ValueError('Error: `winSizes[-1]` must be smaller than the input vector length.')
        if winSizes[0] < (polOrd + 2):
            raise ValueError('Error: `winSizes[0]` must be at least equal to {}.'.format(polOrd + 2))

        self.nRho = np.array(winSizes, dtype=ctypes.c_int)
        nLen = len(self.nRho)
        Fxy = np.zeros((nLen, ), dtype=ctypes.c_double)

        self.cy_flucCompute(np.array(self.tsVec1, dtype=ctypes.c_double), np.array(self.tsVec2,
                            dtype=ctypes.c_double), self.nRho, Fxy, polOrd, False, overlap, revSeg)
        if verbose:
            print('DCCA between series 1 and 2 computed.')
            
        Fxx = self.computeFlucVecSameTs(self.tsVec1, self.nRho, polOrd, overlap, revSeg)
        if verbose:
            print('DCCA between series 1 and 1 computed.')
            
        Fyy = self.computeFlucVecSameTs(self.tsVec2, self.nRho, polOrd, overlap, revSeg)
        if verbose:
            print('DCCA between series 2 and 2 computed.')

        self.rho = np.zeros((nLen, ), dtype=float)
        for i in range(nLen):
            self.rho[i] = Fxy[i] / (Fxx[i] * Fyy[i])

        return self.nRho, self.rho

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    cpdef rhoThresholds(self, int L, np.ndarray[np.int64_t, ndim=1, mode='c'] winSizes, int nSim, double confLvl, int polOrd=1, bint verbose=False):
        """Computation of the cross-correlation index's confidence levels in each window.

        Parameters
        ----------
        L : int
            Size of the random time series used to evaluate confidence levels.
        winSizes : numpy ndarray
            Array of window's sizes.
        nSim : int
            Number of times the cross-correlation index between two random time series
            is computed in order to evaluate the confidence levels.
        confLvl : float
            Confidence level.
        polOrd : int, optional
            Order of the polynomial to be fitted in each window (default : 1).
        verbose : bool, optional
            Verbosity (default : False).

        Returns
        -------
        numpy ndarray
            Array of window's sizes.
        numpy ndarray
            Array containing the first confidence interval.
        numpy ndarray
            Array containing the second confidence interval.
        """
        cdef np.ndarray[np.float64_t, ndim=2, mode='c'] rho_all
        cdef np.ndarray[np.float64_t, ndim=1, mode='c'] ran1, ran2, vecfx, vecfy, vecfxy
        cdef int nLen

        if polOrd < 1:
            raise ValueError('Error: Polynomial order must be greater than 0.')
        if len(winSizes) > 1:
            if winSizes[len(winSizes)-1] <= winSizes[0]:
                raise ValueError('Error: `winSizes[-1]` must be greater than variable `winSizes[0]`.')
        if winSizes[len(winSizes)-1] > L:
            raise ValueError('Error: `winSizes[-1]` must be smaller than `L`.')
        if winSizes[0] < (polOrd + 2):
            raise ValueError('Error: `winSizes[0]` must be at least equal to {}.'.format(polOrd + 2))
        if nSim < 1:
            raise ValueError('Error: Number of simulations must be greater than 0.')
        if confLvl < 0 or confLvl > 1:
            raise ValueError('Error: Confidence level must be included in the interval [0,1].')

        self.nThr = np.array(winSizes, dtype=ctypes.c_int)
        nLen = len(self.nThr)
        self.confUp = np.zeros((nLen, ), dtype=ctypes.c_double)
        self.confDown = np.zeros((nLen, ), dtype=ctypes.c_double)
        rho_all = np.zeros((nSim, nLen), dtype=ctypes.c_double)
        
        for i in range(nSim):
            if verbose:
                print('Simulation number {}'.format(i + 1))
                
            ran1 = np.random.randn(L)
            ran1 = np.cumsum(ran1 - np.mean(ran1))
            ran2 = np.random.randn(L)
            ran2 = np.cumsum(ran2 - np.mean(ran2))
            vecfx = np.zeros((nLen, ), dtype=ctypes.c_double)
            vecfy = np.zeros((nLen, ), dtype=ctypes.c_double)
            vecfxy = np.zeros((nLen, ), dtype=ctypes.c_double)
            
            self.cy_flucCompute(ran1, ran2, self.nThr, vecfxy, polOrd, False, False, False)
            self.cy_flucCompute(ran1, ran1, self.nThr, vecfx, polOrd, True, False, False)
            self.cy_flucCompute(ran2, ran2, self.nThr, vecfy, polOrd, True, False, False)
            
            for j in range(nLen):
                rho_all[i, j] = vecfxy[j] / (vecfx[j] * vecfy[j])
                
        self.confUp = np.quantile(rho_all, confLvl, axis=0)
        self.confDown = np.quantile(rho_all, 1 - confLvl, axis=0)
        
        return self.nThr, self.confUp, self.confDown

    def saveObject(self, outFileName):
        """Save current object state to binary file.
        
        Parameters
        ----------
        outFileName : str
            Output binary file. `.fathon` extension will be appended to the file name.
        """
        saveDict = {}
        saveDict['kind'] = 'dcca'
        saveDict['tsVec1'] = self.tsVec1.tolist()
        saveDict['tsVec2'] = self.tsVec2.tolist()
        try:
            saveDict['n'] = self.n.tolist()
        except:
            saveDict['n'] = []
        try:
            saveDict['F'] = self.F.tolist()
        except:
            saveDict['F'] = []
        try:
            saveDict['nRho'] = self.nRho.tolist()
        except:
            saveDict['nRho'] = []
        try:
            saveDict['rho'] = self.rho.tolist()
        except:
            saveDict['rho'] = []
        try:
            saveDict['nThr'] = self.nThr.tolist()
        except:
            saveDict['nThr'] = []
        try:
            saveDict['confUp'] = self.confUp.tolist()
        except:
            saveDict['confUp'] = []
        try:
            saveDict['confDown'] = self.confDown.tolist()
        except:
            saveDict['confDown'] = []
        saveDict['isComputed'] = self.isComputed

        f = open(outFileName + '.fathon', 'wb')
        pickle.dump(saveDict, f)
        f.close()