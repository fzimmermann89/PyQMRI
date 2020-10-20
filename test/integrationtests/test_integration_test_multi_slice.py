#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Mon Aug 12 11:26:41 2019

@author: omaier
"""
import pytest
import os
import pyqmri
import shutil
import h5py
import numpy as np


@pytest.mark.integration_test
def test_VFA_model_kspace_TGV_cart_multislice(gen_multislice_data):
    assert pyqmri.run(data=os.getcwd()+'/test/VFA_cart_test.h5',
                      model='VFA',
                      config=os.getcwd()+'/test/default.ini',
                      trafo=False,
                      slices=4
                      ) is None


@pytest.mark.integration_test
def test_VFA_model_kspace_TGV_cart_multislice_streamed(gen_multislice_data):
    assert pyqmri.run(data=os.getcwd()+'/test/VFA_cart_test.h5',
                      model='VFA',
                      config=os.getcwd()+'/test/default.ini',
                      trafo=False,
                      slices=4,
                      streamed=1,
                      devices=0,
                      ) is None


@pytest.mark.integration_test
def test_VFA_model_kspace_TV_cart_multislice_streamed(gen_multislice_data):
    assert pyqmri.run(data=os.getcwd()+'/test/VFA_cart_test.h5',
                      model='VFA',
                      config=os.getcwd()+'/test/default.ini',
                      trafo=False,
                      slices=4,
                      streamed=1,
                      devices=0,
                      reg_type='TV'
                      ) is None


@pytest.fixture(scope="function")
def gen_multislice_data():
    file = h5py.File(os.getcwd()+'/test/VFA_cart_smalltest.h5', 'r')

    Coils = file["Coils"][()]
    real_dat = file["real_dat"][()]
    imag_dat = file["imag_dat"][()]
    images = file["images"][()]
    fa_corr = file["fa_corr"][()]

    image_dimensions = file.attrs["image_dimensions"]
    fa = file.attrs["fa"][()]
    TR = file.attrs["TR"]

    file_out = h5py.File(os.getcwd()+'/test/VFA_cart_test.h5', 'w')

    slices = 4

    Coils = np.repeat(Coils, repeats=slices, axis=1)
    real_dat = np.repeat(real_dat, repeats=slices, axis=2)
    imag_dat = np.repeat(imag_dat, repeats=slices, axis=2)
    fa_corr = np.repeat(fa_corr, repeats=slices, axis=0)
    images = np.repeat(images, repeats=slices, axis=1)

    file_out["Coils"] = Coils
    file_out["real_dat"] = real_dat
    file_out["imag_dat"] = imag_dat
    file_out["fa_corr"] = fa_corr
    file_out["images"] = images

    image_dimensions[2] = slices

    file_out.attrs["TR"] = TR
    file_out.attrs["fa"] = fa
    file_out.attrs["flip_angle(s)"] = fa
    file_out.attrs["image_dimensions"] = image_dimensions
    file_out.close()
    file.close()


@pytest.fixture(autouse=True, scope="session")
def clean_up():
    yield
    try:
        shutil.rmtree(os.getcwd()+'/test/PyQMRI_out')
    except OSError as e:
        print("Error: %s - %s." % (e.filename, e.strerror))
