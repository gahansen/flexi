#include "flexi.h"

!===================================================================================================================================
!> \brief Module containing routines to write structured data (points, lines and planes) to the vtk data format. 
!>
!> The structure is as follows: All points will be written to a common .vts file, named ProjectName_points.vts. All lines
!> and all planes will be written to a seperate .vts file, which will be named after the name of the line or plane.
!> A .vtm file will also be produced, allowing to open all the different types at once.
!===================================================================================================================================
MODULE MOD_VTKStructuredOutput
! MODULES
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
TYPE RPPlane
  CHARACTER(LEN=255)      :: name
  INTEGER                 :: nRPs(2)
  REAL,ALLOCATABLE        :: Coords(:,:,:)
  REAL,ALLOCATABLE        :: Val(:,:,:)
END TYPE

TYPE RPLine
  CHARACTER(LEN=255)      :: name
  INTEGER                 :: nRPs
  REAL,ALLOCATABLE        :: Coords(:,:)
  REAL,ALLOCATABLE        :: Val(:,:)
END TYPE

TYPE RPPoint
  INTEGER                 :: nRPs
  REAL,ALLOCATABLE        :: Coords(:,:)
  REAL,ALLOCATABLE        :: Val(:,:)
END TYPE

INTERFACE WriteStructuredDataToVTK
  MODULE PROCEDURE WriteStructuredDataToVTK
END INTERFACE

PUBLIC:: WriteStructuredDataToVTK
!===================================================================================================================================

CONTAINS


!===================================================================================================================================
!> Subroutine to write 2D or 3D point data to VTK format
!===================================================================================================================================
SUBROUTINE WriteStructuredDataToVTK(ProjectName,nLines,nPlanes,RPPoints,RPLines,RPPlanes,withData,nVal,VarNames)
! MODULES
USE MOD_Globals
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)          :: Projectname       !< Output file name
INTEGER,INTENT(IN)                   :: nLines            !< Number of lines to visualize 
INTEGER,INTENT(IN)                   :: nPlanes           !< Number of planes to visualize
TYPE(RPPoint),INTENT(IN)             :: RPPoints          !< Type containing data on points
TYPE(RPLine),INTENT(IN)              :: RPLines(nLines)   !< Type containing data on lines
TYPE(RPPlane),INTENT(IN)             :: RPPlanes(nPlanes) !< Type containing data on planes
LOGICAL,INTENT(IN)                   :: withData          !< If set to false, only the coordinates will be visualized
INTEGER,INTENT(IN)                   :: nVal              !< Number of variables to visualize
CHARACTER(LEN=*),INTENT(IN),OPTIONAL :: VarNames(nVal)    !< Names of variables to visualize
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                     :: ivtk=44
INTEGER                     :: nBytes,Offset
REAL(KIND=4)                :: FLOATdummy
CHARACTER(LEN=35)           :: StrOffset,TempStr1,TempStr2
CHARACTER(LEN=200)          :: Buffer
CHARACTER(LEN=200)          :: Buffer2
CHARACTER(LEN=255)          :: ZoneTitle
CHARACTER(LEN=255)          :: FileName
CHARACTER(LEN=1)            :: lf
INTEGER                     :: iVar,iPlane,iLine,nSets,iSet,nPoints
CHARACTER(LEN=255),ALLOCATABLE :: ZoneNames(:),FileNamesVTS(:)
!===================================================================================================================================
! Check if variable names and size has been supplied if data should be written
IF ((withData).AND.(.NOT.PRESENT(VarNames))) STOP 'Variables have not been specified in the VTK output routine!'

WRITE(UNIT_stdOut,'(A,I1,A)')" WRITE Structured data to VTK ... "

nPoints = RPPoints%nRPs ! Number of single points to visualize
nSets= MERGE( 1, 0, nPoints.GT.0) +nLines+nPlanes
ALLOCATE(FileNamesVTS(nSets))
ALLOCATE(ZoneNames(nSets))
iSet=0

! Points
IF(nPoints.GT.0) THEN
  FileName=TRIM(ProjectName)//'_Points.vts'
  iSet=iSet+1
  FileNamesVTS(iSet)=FileName
  ZoneNames(iSet)='Points'
  WRITE(UNIT_stdOut,'(A,A)')' WRITING POINT RP POSITIONS TO ',FileName

  ! write header of VTK file
  ! Line feed character
  lf = char(10)

  ! Write file
  OPEN(UNIT=ivtk,FILE=TRIM(FileName),ACCESS='STREAM')
  ! Write header
  Buffer='<?xml version="1.0"?>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='<VTKFile type="StructuredGrid" version="0.1" byte_order="LittleEndian">'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify file type
  Buffer ='  <StructuredGrid WholeExtent="'
  Buffer2='    <Piece Extent="'
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') nPoints-1
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') 0 
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') 0
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) // '">'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) // '">'//lf;WRITE(ivtk) TRIM(Buffer2)

  ! Specify point data
  Buffer='      <PointData>'//lf;WRITE(ivtk) TRIM(Buffer)
  Offset=0
  IF (withData) THEN
    DO iVar = 1,nVal
      WRITE(StrOffset,'(I16)')Offset
      Buffer='        <DataArray type="Float32" Name="'//TRIM(VarNames(iVar))//'" NumberOfComponents="1" format="appended" '// &
                       'offset="'//TRIM(ADJUSTL(StrOffset))//'"/>'//lf;WRITE(ivtk) TRIM(Buffer)
      Offset = Offset +nPoints*SIZEOF_F(FLOATdummy)
    END DO
  END IF
  Buffer='      </PointData>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify cell data
  Buffer='      <CellData> </CellData>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify coordinate data
  Buffer='      <Points>'//lf;WRITE(ivtk) TRIM(Buffer)
  WRITE(StrOffset,'(I16)')Offset
  Buffer='        <DataArray type="Float32" Name="Coordinates" NumberOfComponents="3" format="appended" '// &
                   'offset="'//TRIM(ADJUSTL(StrOffset))//'"/>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='      </Points>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='    </Piece>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='  </StructuredGrid>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Prepare append section
  Buffer='  <AppendedData encoding="raw">'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Write leading data underscore
  Buffer='_';WRITE(ivtk) TRIM(Buffer)

  nBytes = nPoints*SIZEOF_F(FLOATdummy) * (3+nVal)
  WRITE(ivtk) nBytes
  IF (withData) WRITE(ivtk) REAL(RPPoints%Val(:,:),4)
  WRITE(ivtk) REAL(RPPoints%Coords(:,:),4)

  ! Footer
  lf = char(10)
  Buffer=lf//'  </AppendedData>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='</VTKFile>'//lf;WRITE(ivtk) TRIM(Buffer)
  CLOSE(ivtk)
END IF

! Lines
DO iLine=1,nLines
  ZoneTitle=TRIM(RPLines(iLine)%name)
  FileName=TRIM(ProjectName)//'_'//TRIM(ZoneTitle)//'.vts'
  iSet=iSet+1
  FileNamesVTS(iSet)=FileName
  ZoneNames(iSet)=TRIM(ZoneTitle)
  WRITE(UNIT_stdOut,'(A,A)')' WRITING LINE RP POSITIONS TO ',FileName

  ! write header of VTK file
  ! Line feed character
  lf = char(10)

  ! Write file
  OPEN(UNIT=ivtk,FILE=TRIM(FileName),ACCESS='STREAM')
  ! Write header
  Buffer='<?xml version="1.0"?>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='<VTKFile type="StructuredGrid" version="0.1" byte_order="LittleEndian">'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify file type
  Buffer ='  <StructuredGrid WholeExtent="'
  Buffer2='    <Piece Extent="'
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') RPLines(iLine)%nRPs-1
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') 0 
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') 0
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) // '">'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) // '">'//lf;WRITE(ivtk) TRIM(Buffer2)

  ! Specify point data
  Buffer='      <PointData>'//lf;WRITE(ivtk) TRIM(Buffer)
  Offset=0
  IF (withData) THEN
    DO iVar = 1,nVal
      WRITE(StrOffset,'(I16)')Offset
      Buffer='        <DataArray type="Float32" Name="'//TRIM(VarNames(iVar))//'" NumberOfComponents="1" format="appended" '// &
                       'offset="'//TRIM(ADJUSTL(StrOffset))//'"/>'//lf;WRITE(ivtk) TRIM(Buffer)
      Offset = Offset + RPLines(iLine)%nRPs*SIZEOF_F(FLOATdummy)
    END DO
  END IF
  Buffer='      </PointData>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify cell data
  Buffer='      <CellData> </CellData>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify coordinate data
  Buffer='      <Points>'//lf;WRITE(ivtk) TRIM(Buffer)
  WRITE(StrOffset,'(I16)')Offset
  Buffer='        <DataArray type="Float32" Name="Coordinates" NumberOfComponents="3" format="appended" '// &
                   'offset="'//TRIM(ADJUSTL(StrOffset))//'"/>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='      </Points>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='    </Piece>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='  </StructuredGrid>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Prepare append section
  Buffer='  <AppendedData encoding="raw">'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Write leading data underscore
  Buffer='_';WRITE(ivtk) TRIM(Buffer)

  nBytes = RPLines(iLine)%nRPs*SIZEOF_F(FLOATdummy) * 3
  WRITE(ivtk) nBytes
  IF (withData) WRITE(ivtk) REAL(RPLines(iLine)%Val(:,:),4)
  WRITE(ivtk) REAL(RPLines(iLine)%Coords(:,:),4)

  ! Footer
  lf = char(10)
  Buffer=lf//'  </AppendedData>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='</VTKFile>'//lf;WRITE(ivtk) TRIM(Buffer)
  CLOSE(ivtk)
END DO

! Planes
DO iPlane=1, nPlanes
  ZoneTitle=TRIM(RPPlanes(iPlane)%name)
  FileName=TRIM(ProjectName)//'_'//TRIM(ZoneTitle)//'.vts'
  iSet=iSet+1
  FileNamesVTS(iSet)=FileName
  ZoneNames(iSet)=TRIM(ZoneTitle)
  WRITE(UNIT_stdOut,'(A,A)')' WRITING PLANE RP POSITIONS TO ',FileName

  ! write header of VTK file
  ! Line feed character
  lf = char(10)

  ! Write file
  OPEN(UNIT=ivtk,FILE=TRIM(FileName),ACCESS='STREAM')
  ! Write header
  Buffer='<?xml version="1.0"?>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='<VTKFile type="StructuredGrid" version="0.1" byte_order="LittleEndian">'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify file type
  Buffer ='  <StructuredGrid WholeExtent="'
  Buffer2='    <Piece Extent="'
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') RPPlanes(iPlane)%nRPs(1)-1
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') RPPlanes(iPlane)%nRPs(2)-1
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) 
  WRITE(TempStr1,'(I16)') 0
  WRITE(TempStr2,'(I16)') 0
  Buffer =TRIM(Buffer)  // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) // '">'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer2=TRIM(Buffer2) // ' ' // TRIM(ADJUSTL(TempStr1)) // ' ' // TRIM(ADJUSTL(TempStr2)) // '">'//lf;WRITE(ivtk) TRIM(Buffer2)

  ! Specify point data
  Buffer='      <PointData>'//lf;WRITE(ivtk) TRIM(Buffer)
  Offset=0
  IF (withData) THEN
    DO iVar = 1,nVal
      WRITE(StrOffset,'(I16)')Offset
      Buffer='        <DataArray type="Float32" Name="'//TRIM(VarNames(iVar))//'" NumberOfComponents="1" format="appended" '// &
                       'offset="'//TRIM(ADJUSTL(StrOffset))//'"/>'//lf;WRITE(ivtk) TRIM(Buffer)
      Offset = Offset + RPPlanes(iPlane)%nRPs(1)*RPPlanes(iPlane)%nRPs(2)*SIZEOF_F(FLOATdummy)
    END DO
  END IF
  Buffer='      </PointData>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify cell data
  Buffer='      <CellData> </CellData>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Specify coordinate data
  Buffer='      <Points>'//lf;WRITE(ivtk) TRIM(Buffer)
  WRITE(StrOffset,'(I16)')Offset
  Buffer='        <DataArray type="Float32" Name="Coordinates" NumberOfComponents="3" format="appended" '// &
                   'offset="'//TRIM(ADJUSTL(StrOffset))//'"/>'//lf;WRITE(ivtk) TRIM(Buffer)
  Offset = Offset + RPPlanes(iPlane)%nRPs(1)*RPPlanes(iPlane)%nRPs(2)*SIZEOF_F(FLOATdummy) * 3
  Buffer='      </Points>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='    </Piece>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='  </StructuredGrid>'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Prepare append section
  Buffer='  <AppendedData encoding="raw">'//lf;WRITE(ivtk) TRIM(Buffer)
  ! Write leading data underscore
  Buffer='_';WRITE(ivtk) TRIM(Buffer)

  nBytes = RPPlanes(iPlane)%nRPs(1)*RPPlanes(iPlane)%nRPs(2)*SIZEOF_F(FLOATdummy) * (3+nVal)
  WRITE(ivtk) nBytes
  IF (withData) WRITE(ivtk) REAL(RPPlanes(iPlane)%Val(:,:,:),4)
  WRITE(ivtk) REAL(RPPlanes(iPlane)%Coords(:,:,:),4)

  ! Footer
  lf = char(10)
  Buffer=lf//'  </AppendedData>'//lf;WRITE(ivtk) TRIM(Buffer)
  Buffer='</VTKFile>'//lf;WRITE(ivtk) TRIM(Buffer)
  CLOSE(ivtk)
END DO

CALL WriteVTKMultiBlockDataSetRP(ProjectName,nSets,FileNamesVTS,ZoneNames)
DEALLOCATE(FileNamesVTS,ZoneNames)

SWRITE(UNIT_stdOut,'(A)',ADVANCE='YES')"DONE"
END SUBROUTINE WriteStructuredDataToVTK



!===================================================================================================================================
!> Links structured VTK data files together
!===================================================================================================================================
SUBROUTINE WriteVTKMultiBlockDataSetRP(ProjectName,nSets,FileNamesVTS,ZoneNames)
! MODULES
USE MOD_Globals
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN) :: ProjectName          !< Projectname
INTEGER, INTENT(IN)         :: nSets                !< Number of VTS files to link
CHARACTER(LEN=*),INTENT(IN) :: FileNamesVTS(nSets)  !< Filenames of structured datasets 
CHARACTER(LEN=*),INTENT(IN) :: ZoneNames(nSets)     !< Zone names of structured datasets 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: ivtk=44
INTEGER            :: iSet
CHARACTER(LEN=200) :: Buffer
CHARACTER(LEN=1)   :: lf
CHARACTER(LEN=35)  :: TempStr1
CHARACTER(LEN=255) :: FileStringOut 
!===================================================================================================================================
FileStringOut=TRIM(ProjectName)//'_RPVisu.vtm'
! write multiblock file
OPEN(UNIT=ivtk,FILE=TRIM(FileStringOut),ACCESS='STREAM')
! Line feed character
lf = char(10)
Buffer='<VTKFile type="vtkMultiBlockDataSet" version="1.0" byte_order="LittleEndian" header_type="UInt64">'//lf
WRITE(ivtk) TRIM(BUFFER)
Buffer='  <vtkMultiBlockDataSet>'//lf;WRITE(ivtk) TRIM(BUFFER)

DO iSet=1,nSets
  WRITE(TempStr1,'(I16)') iSet
  Buffer='    <DataSet index="' // TRIM(ADJUSTL(TempStr1)) // '" name="' // TRIM(ZoneNames(iSet)) // '" file="'&
            //TRIM(FileNamesVTS(iSet))// '">'//lf;WRITE(ivtk) TRIM(BUFFER)
  Buffer='    </DataSet>'//lf;WRITE(ivtk) TRIM(BUFFER)
END DO

Buffer='  </vtkMultiBlockDataSet>'//lf;WRITE(ivtk) TRIM(BUFFER)
Buffer='</VTKFile>'//lf;WRITE(ivtk) TRIM(BUFFER)
CLOSE(ivtk)
END SUBROUTINE WriteVTKMultiBlockDataSetRP

END MODULE MOD_VTKStructuredOutput
