!=================================================================================================================================
! Copyright (c) 2016  Prof. Claus-Dieter Munz
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "flexi.h"

!===================================================================================================================================
!> ??????????
!===================================================================================================================================
PROGRAM posti_filter_hit
! MODULES
USE MOD_Globals
USE MOD_Filter_HIT
USE MOD_Filter_HIT_Vars
USE MOD_DG_Vars,                 ONLY: U,Ut
USE MOD_Mesh,                    ONLY: DefineParametersMesh,InitMesh,FinalizeMesh
USE MOD_Mesh_Vars,               ONLY: nElems_IJK,MeshFile
USE MOD_Mesh_ReadIn,             ONLY: ReadIJKSorting
USE MOD_Output,                  ONLY: DefineParametersOutput
USE MOD_Interpolation,           ONLY: DefineParametersInterpolation,InitInterpolation,FinalizeInterpolation
USE MOD_IO_HDF5,                 ONLY: DefineParametersIO_HDF5,InitIOHDF5
USE MOD_HDF5_Output,             ONLY: WriteState
USE MOD_StringTools,             ONLY: STRICMP,GetFileExtension
USE MOD_ReadInTools
USE MOD_Commandline_Arguments
USE MOD_FFT,                     ONLY: InitFFT,FinalizeFFT
USE MOD_FFT_Vars,                ONLY: N_FFT,N_Visu
USE MOD_MPI,                     ONLY: DefineParametersMPI,InitMPI
#if USE_MPI
USE MOD_MPI,                     ONLY: InitMPIvars,FinalizeMPI
#endif
#if USE_OPENMP
USE OMP_Lib
#endif
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                            :: iArg
REAL                               :: Time
#if USE_MPI
REAL                               :: limit,nTotal
#endif
CHARACTER(LEN=255)                 :: InputStateFile
CHARACTER(LEN=255)                 :: MeshFile_old = " "      ! MeshFile of last state file
INTEGER                            :: N_HDF5_old=0
LOGICAL                            :: changedMeshFile=.FALSE. ! True if mesh between states changed
LOGICAL                            :: changedN       =.FALSE. ! True if N between states changes
!===================================================================================================================================
CALL SetStackSizeUnlimited()
CALL InitMPI()
IF (nProcessors.GT.1) CALL CollectiveStop(__STAMP__, &
     'This tool is designed only for single execution!')

CALL ParseCommandlineArguments()

SWRITE(UNIT_stdOut,'(132("="))')
SWRITE(UNIT_stdOut,'(A)') &
    " ||==========================================||                                                           "
SWRITE(UNIT_stdOut,'(A)') &
    " ||         Spectral filter for HIT          ||                                                           "
SWRITE(UNIT_stdOut,'(A)') &
    " ||==========================================||                                                           "
SWRITE(UNIT_stdOut,'(A)')
SWRITE(UNIT_stdOut,'(132("="))')

! Define Parameters
CALL DefineParametersInterpolation()
CALL DefineParametersMPI()
CALL DefineParametersIO_HDF5()
CALL DefineParametersOutput()
CALL DefineParametersMesh()
!=====================================
CALL prms%SetSection("filterHIT")
CALL prms%CreateIntOption("N_Filter" , "Cutoff filter")
CALL prms%CreateIntOption("N_Visu"   , "Polynomial degree to perform DFFT on")

! check for command line argument --help or --markdown
IF (doPrintHelp.GT.0) THEN
  CALL PrintDefaultParameterFile(doPrintHelp.EQ.2, Args(1))
  STOP
END IF
! check if parameter file is given
IF ((nArgs.LT.1).OR.(.NOT.(STRICMP(GetFileExtension(Args(1)),'ini')))) THEN
  CALL CollectiveStop(__STAMP__,'ERROR - Invalid syntax. Please use: init_hit [prm-file]')
END IF
! Parse parameters
CALL prms%read_options(Args(1))
ParameterFile = Args(1)

! Readin Parameters
N_Filter = GETINT('N_Filter','-1')
N_Visu   = GETINT('N_Visu')
MeshFile = GETSTR('MeshFile','')

! Overwrite local meshfile from userblock if present
IF (TRIM(MeshFile).EQ.'') OverwriteMeshFile=.FALSE.

! Initialize IO
CALL InitIOHDF5()

! Loop over all files specified on commandline
DO iArg=2,nArgs
  Time = OMP_FLEXITIME()

  InputStateFile = Args(iArg)

  SWRITE(UNIT_stdOut,'(132("="))')
  SWRITE(UNIT_stdOut,'(A,I5,A,I5,A)') ' PROCESSING FILE ',iArg-1,' of ',nArgs-1,' FILES.'
  SWRITE(UNIT_stdOut,'(A,A,A)') ' ( "',TRIM(InputStateFile),'" )'
  SWRITE(UNIT_stdOut,'(132("="))')

  ! Read attributes and solution from state file
  CALL ReadOldStateFile(InputStateFile)

  ! Check if input attributes have changed since last state file
  IF(TRIM(MeshFile).NE.TRIM(MeshFile_old)) changedMeshFile =.TRUE.
  IF(N_HDF5.NE.N_HDF5_old)                 changedN        =.TRUE.

  ! Re-initialize interpolation and re-allocate DG solution array if N has changed
  IF(changedN) THEN
    CALL FinalizeInterpolation()
    CALL InitInterpolation(N_HDF5)
  END IF

  ! Re-initialize mesh if it has changed
  IF(changedMeshFile) THEN
    SWRITE(UNIT_stdOUT,*) "INITIALIZING MESH FROM FILE """,TRIM(MeshFile),""""
    CALL FinalizeMesh()
    CALL FinalizeMPI()
    CALL DefineParametersMesh()
    CALL InitMesh(MeshMode=0,MeshFile_IN=MeshFile)
    CALL ReadIJKSorting() ! Read global xyz sorting of structured mesh

    ! Currently only cubic meshes are allowed!
    IF(.NOT.((nElems_IJK(1).EQ.nElems_IJK(2)).AND.(nElems_IJK(1).EQ.nElems_IJK(3)))) THEN
      CALL ABORT(__STAMP__,'Mesh does not have the same amount of elements in x,y and z!')
    END IF

    ! Get new number of points for fourier analysis
    N_FFT=(N_Visu+1)*nElems_IJK(1)
  END IF

  IF(changedMeshFile .OR. changedN) THEN
#if USE_MPI
    nTotal=REAL(nVar_HDF5*(N_HDF5+1)**3*nElems_HDF5)
    IF(FieldDataExists) nTotal=MAX(nTotal,REAL(nVarField_HDF5*(N_HDF5+1)**3*nElems_HDF5))
    !limit=(2**31-1)/8.
    limit=2**28-1/8. ! max. 32 bit integer / 8
    IF (nTotal.GT.limit) THEN
      WRITE(UNIT_StdOut,'(A,F13.0,A)')' Input state file size is too big! Total array size may not exceed', limit, ' entries!'
      WRITE(UNIT_StdOut,'(A)')' Lower number of elements or compile without MPI'
      STOP
    END IF
#endif

    CALL FinalizeFFT()
    CALL InitFFT()
  END IF

  ! Transform global solution into Fourier space and apply filter there.
  CALL FourierFilter(nVar_HDF5,U)
  IF(FieldDataExists) CALL FourierFilter(nVarField_HDF5,Ut)

  ! Write State-File
  CALL WriteNewStateFile()

  ! To determine whether meshfile or N changes
  MeshFile_old    = MeshFile
  N_HDF5_old      = N_HDF5
  changedMeshFile = .FALSE.
  changedN        = .FALSE.

  ! Deallocate DG solution array for next file
  DEALLOCATE(U)
  IF(FieldDataExists) DEALLOCATE(Ut)

  SWRITE(UNIT_stdOut,'(132("="))')
  SWRITE(UNIT_stdOut,'(A,A,A,F0.3,A)') ' PROCESSED FILE ',TRIM(InputStateFile),' in [',OMP_FLEXITIME()-Time,'s]'
END DO !iArg=1,nArgs

! Finalize everything
CALL FinalizeParameters()
CALL FinalizeInterpolation()
CALL FinalizeMesh()
CALL FinalizeFFT()
#ifdef MPI
CALL MPI_BARRIER(MPI_COMM_WORLD,iError)
CALL MPI_FINALIZE(iError)
IF(iError .NE. 0) STOP 'MPI finalize error'
CALL FinalizeMPI()
#endif

SWRITE(UNIT_stdOut,'(132("="))')
SWRITE(UNIT_stdOut,'(A)') ' filterHIT FINISHED! '
SWRITE(UNIT_stdOut,'(132("="))')

END PROGRAM posti_filter_hit
