from django.http import HttpResponseBadRequest, HttpResponse, HttpResponseServerError
from django.views import View

from adapters.camera.configs.camera_config_service import CameraConfigService
from adapters.camera.ctrl.camera_ctrl_service import CameraCtrlService
from business.camera.exceptions import CameraNotFoundException, CameraException, InvalidConfigException
from camera_ctrl.api_exceptions import CameraNotFoundApiException
from shared.di import obj_graph


class CameraSetConfigView(View):
    camera_ctrl_service = obj_graph().provide(CameraCtrlService)
    camera_config_service = obj_graph().provide(CameraConfigService)

    def post(self, request, *args, **kwargs):
        camera_id = kwargs['camera_id']
        config_name = kwargs['config_name']
        config_value = request.GET.get('value')

        try:
            if camera_id.lower() == 'first':
                camera = self.camera_ctrl_service.cameras_get_first()
                if camera is None:
                    raise CameraNotFoundException()
                camera_id = camera.id

            self.camera_config_service.set_config(
                camera_id=camera_id,
                config_name=config_name,
                config_value=config_value)

            current_config = self.camera_config_service.get_config(
                camera_id=camera_id,
                config_name=config_name)

            managed_to_change = (str(current_config.value) == config_value)

            if not managed_to_change:
                error = f'Failed to change {config_name} to {config_value}'
                return HttpResponseBadRequest(content=error)

            return HttpResponse(content=f'Changed {config_name} to {config_value}')

        except CameraNotFoundException:
            return CameraNotFoundApiException(camera_id=camera_id)

        except InvalidConfigException as e:
            return HttpResponseBadRequest(content=str(e))

        except CameraException as e:
            return HttpResponseServerError(content=str(e))
